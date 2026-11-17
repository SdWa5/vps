# Sandboxes for third-party projects

A project this host runs for someone else gets a **sandbox**: a unix account of its own with its own
rootless Docker daemon. A container escape then lands as an unprivileged uid instead of root next to
Vaultwarden. The first sandbox is `chimodiazz` ([chimodiazz.md](chimodiazz.md)), set up on
2026-11-17. The tool is `tools/sandbox/sandbox.sh`.

## What a sandbox is

| Part | Value |
|---|---|
| Account | `<name>`, shell `nologin`, member of the group `sandbox`, its own subuid and subgid range of 65536 |
| Home | `/opt/docker/sandbox/<name>`, mode 0700; `/opt/docker/sandbox` is 0711 and git-ignored |
| Daemon | Docker's rootless `dockerd` as the account's systemd user unit `docker.service`, with Docker's defaults (slirp4netns, `--disable-host-loopback`, builtin port driver); linger keeps it running without a login |
| Limits | `/etc/systemd/system/user-<uid>.slice.d/50-sandbox.conf`: `MemoryMax`, `TasksMax`, `CPUQuota` |
| Compose file | tracked at `projects/<name>/docker-compose.yml`; the home is its project directory, so relative bind mounts land in the home |
| Data | bind mounts in the home, owned by the account's subuids (container uid n is host uid `subuid_start + n - 1`, container root is the account) |

**Root acts on a sandbox only as the sandbox account**, through `as_sandbox` in
`monitoring/lib.sh` (`setpriv` to the account with a reset environment, its `XDG_RUNTIME_DIR` and
`DOCKER_HOST`). The sandbox's daemon, `~/.docker` config and code therefore never run with root's
rights. Root writes into a home only while creating it. restic's read-only, non-following backup is
the one reader with root's rights.

## What a sandbox reaches

| Reaches | Does not reach |
|---|---|
| the internet | host loopback, the Caddy admin API on 2019 included |
| the host's public address on tcp 80 and 443 and udp 443, like anyone outside | the host's other ports, ssh included |
| | private, shared and link-local ranges, which hold the Docker bridges of the root daemon |
| | the stack's git-ignored data and `.git` in `/opt/docker`, `/root`, `/var/lib/docker`, `docker.sock` |
| | other sandboxes' homes |

A rootless container's traffic leaves through slirp4netns, a process of the account in the host's
network namespace, and locally originated traffic never passes `DOCKER-USER`. So the firewall
(`hardening/firewall/sdwa5-firewall.sh`) sends every packet of a sandbox account's uid and subuid
range through `SANDBOX-OUT` and `SANDBOX-POLICY` in `OUTPUT`. The subuid range is matched too,
because the account can give its own processes a subuid through `newuidmap`.

`prepare-host` closed every git-ignored path and `.git` of `/opt/docker` to "other" (`chmod o-rwx`,
not recursive). Bind mounts resolve as root, so no container noticed. Tracked files stay readable,
and they hold no secret by design. A new data directory must be created closed, or the hourly check
reports it.

`monitoring/sandbox-check.sh` probes all of this as each sandbox account every hour, see
[monitoring.md](monitoring.md#sandbox-check).

## Limits

- Rootless containers run without AppArmor profiles; seccomp and the user namespace remain.
- Disk is shared and only watched as a whole by vps-health; TODO proposes a quota.
- Named volumes live in the daemon's data-root `~/.local/share/docker`, which restic excludes along
  with the images. A sandbox project keeps its data in bind mounts in the home.
- A sandbox account still sees other users' processes in `ps`, can read `/var/log/cron.log`, and
  can send mail through `smtp-relay.gmail.com` like any process here. TODO.md has proposals for each.
- Containers of a sandbox are not in the root daemon, so the container lists of `vps-health.sh`,
  `database-backup.sh` and `security-recheck.sh` do not see them yet (TODO proposal for the return
  of Chimo Diazz).

## Runbook

All commands as root on the host, in `/opt/docker`.

```bash
# Once per host: packages, group, /opt/docker/sandbox, private data closed. Idempotent.
tools/sandbox/sandbox.sh prepare-host --dry-run
tools/sandbox/sandbox.sh prepare-host

# A new sandbox. Re-running it on an existing sandbox repeats everything but the account and home.
tools/sandbox/sandbox.sh create <name> --dry-run
tools/sandbox/sandbox.sh create <name> --memory 1536M --cpus 2 --tasks 4096

# Compose and any other command as the account.
tools/sandbox/sandbox.sh compose <name> --profile <profile> up -d
tools/sandbox/sandbox.sh run <name> docker ps -a
```

**Files owned by subuids** (a container's data) are read or changed from inside the daemon's user
namespace, where they carry their container uids. Stdin passes through, which is how data is
imported without root writing into the home:

```bash
uid="$(id -u <name>)"
child_pid="$(tools/sandbox/sandbox.sh run <name> cat "/run/user/$uid/dockerd-rootless/child_pid")"
tools/sandbox/sandbox.sh run <name> \
    nsenter --user --preserve-credentials --target "$child_pid" -- \
    tar --numeric-owner --same-owner --same-permissions --extract --file - \
        --directory "/opt/docker/sandbox/<name>" \
    < archive.tar
```

This is `dockerd-rootless-setuptool.sh nsenter` without its mount and network namespaces, called
directly because the setuptool's `getopt` parses the command's options.

**A Docker engine upgrade** upgrades `docker-ce-rootless-extras` to the same version
([maintenance.md](maintenance.md)) and then restarts each sandbox daemon:
`systemctl --user --machine=<name>@ restart docker`.

**Removing a sandbox** is done by hand: stop its containers,
`systemctl --user --machine=<name>@ disable --now docker`, `loginctl disable-linger <name>`,
`userdel <name>`, delete `/etc/systemd/system/user-<uid>.slice.d/50-sandbox.conf`, `systemctl
daemon-reload`, `systemctl restart sdwa5-firewall`, and remove the home from inside the daemon's
namespace before the daemon stops, or as root after looking at it.
