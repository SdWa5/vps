#!/usr/bin/env bash
#
# Sandboxes for third-party projects: one unix account per project, running its
# own rootless Docker daemon, so a container escape lands as an unprivileged uid
# instead of root. See docs/sandbox.md.
#
# Root acts on a sandbox only as the sandbox account (as_sandbox in
# monitoring/lib.sh), never by opening paths inside its home after creating it.
#
# Usage, on the host as root:
#   tools/sandbox/sandbox.sh prepare-host [--dry-run]
#   tools/sandbox/sandbox.sh create NAME [--memory 1536M] [--cpus 2] [--tasks 4096] [--dry-run]
#   tools/sandbox/sandbox.sh run NAME COMMAND...
#   tools/sandbox/sandbox.sh compose NAME COMPOSE-ARGS...
#
#   prepare-host  installs the rootless packages (docker-ce-rootless-extras pinned
#                 to docker-ce's version), creates the group "sandbox" and
#                 /opt/docker/sandbox (0711), and closes every git-ignored path
#                 and .git of /opt/docker to "other" (chmod o-rwx, not recursive).
#   create        adds the account NAME with home /opt/docker/sandbox/NAME (0700)
#                 and its own subuid range, limits its user slice, enables linger,
#                 installs Docker's rootless daemon as its user unit with Docker's
#                 defaults and reloads the firewall, which then filters its uids.
#   run           runs COMMAND as the account, in its home, with its DOCKER_HOST.
#   compose       docker compose for projects/NAME/docker-compose.yml, with the
#                 home as project directory, so relative volumes land there.
#
# --dry-run prints every changing command instead of running it and is allowed
# without root. Both prepare-host and create are idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=monitoring/lib.sh
. "$SCRIPT_DIR/../../monitoring/lib.sh"

SUBUID_FILE="${SUBUID_FILE:-/etc/subuid}"
SUBGID_FILE="${SUBGID_FILE:-/etc/subgid}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SANDBOX_RUN_DIR="${SANDBOX_RUN_DIR:-/run/user}"
# Test hook: the effective uid the root check sees.
SANDBOX_EUID="${SANDBOX_EUID:-$EUID}"
DRY_RUN=0

usage() {
    sed -n '/^# Usage/,/^# without root/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Runs a changing command, or prints it under --dry-run.
run_step() {
    if (( DRY_RUN )); then
        printf 'would run: %s\n' "$*"
        return 0
    fi
    "$@"
}

# write_root_file PATH CONTENT: a root-owned 0644 file, or its content under --dry-run.
write_root_file() {
    local path="$1"
    local content="$2"
    if (( DRY_RUN )); then
        printf 'would write %s:\n%s\n' "$path" "$content"
        return 0
    fi
    install -d -m 0755 -o root -g root "$(dirname "$path")"
    printf '%s' "$content" > "$path.tmp"
    chmod 0644 "$path.tmp"
    mv "$path.tmp" "$path"
}

require_root() {
    (( DRY_RUN || SANDBOX_EUID == 0 )) || die "Run as root, or with --dry-run."
}

is_sandbox_member() {
    [[ " $(sandbox_members) " == *" $1 "* ]]
}

require_sandbox_member() {
    is_sandbox_member "$1" || die "$1 is not a sandbox account (group ${SANDBOX_GROUP:-sandbox})."
}

prepare_host() {
    local docker_version
    local path
    require_root
    docker_version="$(dpkg-query -W -f='${Version}' docker-ce)"
    [[ -n "$docker_version" ]] || die "docker-ce is not installed."
    run_step apt-get install -y --no-install-recommends \
        uidmap dbus-user-session slirp4netns "docker-ce-rootless-extras=$docker_version"
    if ! getent group "${SANDBOX_GROUP:-sandbox}" >/dev/null; then
        run_step groupadd --system "${SANDBOX_GROUP:-sandbox}"
    fi
    run_step install -d -m 0711 -o root -g root "$COMPOSE_DIR/sandbox"

    # Private data: the stack's ignored data and .git must not be readable by a
    # sandbox account. Bind mounts resolve as root, so no container is affected.
    while IFS= read -r path; do
        printf 'closing %s %s\n' "$(stat -c '%a %U:%G' "$COMPOSE_DIR/$path")" "$path"
        run_step chmod o-rwx -- "$COMPOSE_DIR/$path"
    done < <(open_private_paths)
}

# Waits up to 15 seconds for the user bus of a freshly lingering account.
wait_for_user_bus() {
    local bus="$1"
    local waited=0
    while [[ ! -S "$bus" ]]; do
        (( waited >= 15 )) && die "No user bus at $bus after 15 s."
        sleep 1
        waited=$((waited + 1))
    done
}

create_sandbox() {
    local name="${1:-}"
    local memory=1536M
    local cpus=2
    local tasks=4096
    local home
    local uid
    local security_options
    [[ -n "$name" ]] || { usage >&2; exit 2; }
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --memory) memory="${2:-}"; shift 2 ;;
            --cpus) cpus="${2:-}"; shift 2 ;;
            --tasks) tasks="${2:-}"; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    require_root
    [[ "$name" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || die "Invalid sandbox name: $name"
    [[ "$memory" =~ ^[0-9]+[KMG]$ ]] || die "--memory takes a size such as 1536M."
    [[ "$cpus" =~ ^[1-9][0-9]*$ ]] || die "--cpus takes a whole number."
    [[ "$tasks" =~ ^[1-9][0-9]*$ ]] || die "--tasks takes a whole number."
    getent group "${SANDBOX_GROUP:-sandbox}" >/dev/null || die "No group sandbox; run prepare-host first."
    command -v dockerd-rootless-setuptool.sh >/dev/null || die "No dockerd-rootless-setuptool.sh; run prepare-host first."

    home="$COMPOSE_DIR/sandbox/$name"
    if getent passwd "$name" >/dev/null; then
        require_sandbox_member "$name"
    else
        # A normal account, not --system, so useradd allocates subuids and subgids.
        run_step useradd --home-dir "$home" --no-create-home --shell /usr/sbin/nologin \
            --user-group --groups "${SANDBOX_GROUP:-sandbox}" "$name"
        run_step install -d -m 0700 -o "$name" -g "$name" "$home"
    fi

    uid="$(getent passwd "$name" | cut -d: -f3 || true)"
    if [[ -z "$uid" ]]; then
        (( DRY_RUN )) || die "useradd left no account $name."
        uid='<uid>'
    elif ! grep -q "^$name:" "$SUBUID_FILE" || ! grep -q "^$name:" "$SUBGID_FILE"; then
        die "$name has no range in $SUBUID_FILE or $SUBGID_FILE."
    fi

    write_root_file "$SYSTEMD_DIR/user-$uid.slice.d/50-sandbox.conf" "# Written by tools/sandbox/sandbox.sh, see docs/sandbox.md.
[Slice]
MemoryMax=$memory
TasksMax=$tasks
CPUQuota=$((cpus * 100))%
"
    run_step systemctl daemon-reload
    run_step loginctl enable-linger "$name"
    if (( ! DRY_RUN )); then
        wait_for_user_bus "$SANDBOX_RUN_DIR/$uid/bus"
    fi
    run_step as_sandbox "$name" env DBUS_SESSION_BUS_ADDRESS="unix:path=$SANDBOX_RUN_DIR/$uid/bus" \
        dockerd-rootless-setuptool.sh install
    # The firewall reads the group on start, so the new uid and range get filtered.
    run_step systemctl restart sdwa5-firewall

    if (( ! DRY_RUN )); then
        security_options="$(as_sandbox "$name" docker info --format '{{json .SecurityOptions}}')"
        [[ "$security_options" == *name=rootless* ]] || die "The daemon of $name does not report rootless: $security_options"
        printf 'Sandbox %s is ready (uid %s).\n' "$name" "$uid"
    fi
}

run_in_sandbox() {
    local name="${1:-}"
    [[ -n "$name" && $# -ge 2 ]] || { usage >&2; exit 2; }
    shift
    require_root
    require_sandbox_member "$name"
    as_sandbox "$name" "$@"
}

compose_in_sandbox() {
    local name="${1:-}"
    [[ -n "$name" && $# -ge 2 ]] || { usage >&2; exit 2; }
    shift
    require_root
    require_sandbox_member "$name"
    as_sandbox "$name" docker compose --project-name "$name" \
        --project-directory "$COMPOSE_DIR/sandbox/$name" \
        -f "$COMPOSE_DIR/projects/$name/docker-compose.yml" "$@"
}

main() {
    local command="${1:-}"
    [[ $# -gt 0 ]] && shift
    case "$command" in
        prepare-host)
            case "${1:-}" in
                --dry-run) DRY_RUN=1 ;;
                '') ;;
                *) die "Unknown option: $1" ;;
            esac
            prepare_host
            ;;
        create) create_sandbox "$@" ;;
        run) run_in_sandbox "$@" ;;
        compose) compose_in_sandbox "$@" ;;
        --help|-h) usage ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
