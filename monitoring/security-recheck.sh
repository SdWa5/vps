#!/usr/bin/env bash
#
# SdWa5 security recheck.
#
# Repeats the exposure, firewall and isolation measurements that the 2026-10-15 hardening work
# (SEC-02 to SEC-07, SEC-25) did by hand several times, so the next acceptance or audit is one
# command. It changes nothing: every probe is a read, a TCP connect or an HTTP GET. The optional
# restore checks create only a temporary database container and volume, see database-restore-check.sh.
#
# The script runs in two places. From a workstation it probes the public side itself and then runs
# its own --host part on the VPS over ssh, merging both into one report. On the VPS, --host probes
# the firewall, the container isolation, the secrets in container environments, the listeners
# dockware's boot hook must have closed, the deployed revision and the deployed config copies.
#
# Usage:
#   security-recheck.sh                external probes here, host probes over ssh
#   security-recheck.sh --external     external probes only
#   security-recheck.sh --host         host probes only (root on the VPS)
#   security-recheck.sh --restore      also run the SQL restore checks on the host
#   security-recheck.sh --strict       a WARN also fails the run
#   security-recheck.sh --help
#
# Output: one "check:subject<TAB>STATUS<TAB>message" line per result, STATUS being OK, WARN or CRIT.
# Exit status: 0 without CRIT, 1 with a CRIT (or a WARN under --strict), 2 for a usage error.
#
# Nothing secret is printed. Responses are reduced to status codes, header names and the HSTS
# max-age; bodies are compared, never shown; .env is never loaded. Container environments are reduced
# to variable names inside the pipe that reads them, so no value reaches a variable.
#
# Environment overrides, set on the machine that runs the part they belong to:
#   RECHECK_SSH_HOST, RECHECK_REMOTE_SCRIPT     where the --host part runs
#   RECHECK_TARGET_V4, RECHECK_TARGET_V6        port scan targets; an empty v6 target skips v6
#   EXTERNAL_TCP_PORTS, EXPECTED_TCP_OPEN       scanned ports and the ones that must answer
#   RECHECK_SITES, HSTS_SITES, HSTS_MIN_AGE     sites that must answer 200, and HSTS on some
#   HTTP3_SITE                                  site probed over HTTP/3
#   BLOCKED_PATHS, CADDY_404_BODY               "site=/path" pairs and Caddy's own 404 body
#   FIREWALL_PORTS, FIREWALL_UDP_PORTS, WAN_INTERFACE
#   ISOLATION_APPS, ISOLATION_SOURCES, ISOLATION_EXPECT_OPEN
#   GATEWAY_OPEN, GATEWAY_CLOSED, NO_EGRESS_CONTAINERS, EGRESS_PROBES, CLOSED_LISTENERS
#   GIT_CHECKOUT_DIR, GIT_BRANCH, DEPLOYED_FILES, DATABASE_BACKUP_CONTAINERS
#   PORT_TIMEOUT, PROBE_TIMEOUT, HTTP_TIMEOUT, RESTORE_CHECK (test hook)

set -uo pipefail

MONITORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$MONITORING_DIR")}"

RECHECK_SSH_HOST="${RECHECK_SSH_HOST:-sdwa5.org}"
RECHECK_REMOTE_SCRIPT="${RECHECK_REMOTE_SCRIPT:-/opt/docker/monitoring/security-recheck.sh}"

RECHECK_TARGET_V4="${RECHECK_TARGET_V4:-sdwa5.org}"
# No AAAA record is published, so IPv6 is reached by its literal address (docs/ssh-hardening.md).
RECHECK_TARGET_V6="${RECHECK_TARGET_V6-2a02:c206:3015:7801::1}"
# The 44 ports of the 2026-10-14 audit's selection plus 33113 and the Paperless publishes 8006 and 8007: well-known services, databases,
# Docker and Caddy admin ports, the loopback publishes of this host and the Minecraft and Ollama
# profiles. A selection, not a full scan.
EXTERNAL_TCP_PORTS="${EXTERNAL_TCP_PORTS:-21 22 23 25 53 80 110 111 135 139 143 443 445 465 587 993 995 1433 2019 2375 2376 3000 3306 3389 5000 5355 5432 5900 6379 8000 8001 8002 8003 8004 8005 8080 8006 8007 8443 8444 9000 9200 11211 11434 25565 27017 33113}"
EXPECTED_TCP_OPEN="${EXPECTED_TCP_OPEN:-22 80 443}"

RECHECK_SITES="${RECHECK_SITES:-sdwa5.org chimodiazz.sdwa5.org vault.sdwa5.org erp.sdwa5.org paper.sdwa5.org paper.ripper.sdwa5.org}"
HSTS_SITES="${HSTS_SITES:-vault.sdwa5.org erp.sdwa5.org paper.sdwa5.org paper.ripper.sdwa5.org}"
HSTS_MIN_AGE="${HSTS_MIN_AGE:-31536000}"
HTTP3_SITE="${HTTP3_SITE:-sdwa5.org}"
BLOCKED_PATHS="${BLOCKED_PATHS:-sdwa5.org=/adminer sdwa5.org=/mailcatcher sdwa5.org=/logs chimodiazz.sdwa5.org=/adminer chimodiazz.sdwa5.org=/mailcatcher chimodiazz.sdwa5.org=/logs vault.sdwa5.org=/admin erp.sdwa5.org=/api/index.php/explorer paper.sdwa5.org=/admin paper.ripper.sdwa5.org=/admin}"
# Caddy's `respond "Not Found" 404`. An upstream 404 has a different body, which is how a variant
# that slipped past the matcher shows up even when the upstream happens to refuse it as well.
CADDY_404_BODY="${CADDY_404_BODY:-Not Found}"

FIREWALL_PORTS="${FIREWALL_PORTS:-22 80 443}"
FIREWALL_UDP_PORTS="${FIREWALL_UDP_PORTS:-443}"
WAN_INTERFACE="${WAN_INTERFACE:-eth0}"

# app=container,container. A container may reach its own application and nothing else.
ISOLATION_APPS="${ISOLATION_APPS:-vault=vaultwarden shop=shopware chimodiazz=chimodiazz_shopware erp=dolibarr,dolibarr_cron,dolibarr_db paper=paperless_sdwa5,paperless_sdwa5_db,paperless_sdwa5_broker paperhome=paperless_home,paperless_home_db,paperless_home_broker backup=restic}"
# The containers probed from. They run third-party or internet-facing code and have bash.
ISOLATION_SOURCES="${ISOLATION_SOURCES:-chimodiazz_shopware shopware dolibarr paperless_sdwa5 paperless_home}"
# The one path inside an application that must stay open, measured 2026-10-15.
ISOLATION_EXPECT_OPEN="${ISOLATION_EXPECT_OPEN:-dolibarr>dolibarr_db:3306 paperless_sdwa5>paperless_sdwa5_db:3306 paperless_sdwa5>paperless_sdwa5_broker:6379 paperless_home>paperless_home_db:3306 paperless_home>paperless_home_broker:6379}"
GATEWAY_OPEN="${GATEWAY_OPEN:-22 80 443}"
GATEWAY_CLOSED="${GATEWAY_CLOSED:-25 2019 3306 8000 8002 8006 8007 8443 33113}"
NO_EGRESS_CONTAINERS="${NO_EGRESS_CONTAINERS:-dolibarr_db paperless_sdwa5_db paperless_sdwa5_broker paperless_home_db paperless_home_broker}"
EGRESS_PROBES="${EGRESS_PROBES:-1.1.1.1:443 9.9.9.9:53}"
# "container:port,port" pairs that must not listen. dockware starts sshd (22) and mailcatcher (1025
# SMTP, 1080 web) on every boot, and hardening/dockware-boot-end.sh stops them again. chimodiazz keeps
# mailcatcher, because its mail still falls back to it, see that script.
CLOSED_LISTENERS="${CLOSED_LISTENERS:-shopware:22,1025,1080 chimodiazz_shopware:22}"

GIT_CHECKOUT_DIR="${GIT_CHECKOUT_DIR:-$COMPOSE_DIR}"
GIT_BRANCH="${GIT_BRANCH:-main}"
DEPLOYED_FILES="${DEPLOYED_FILES:-Caddyfile:/etc/caddy/Caddyfile hardening/fail2ban/jail.local:/etc/fail2ban/jail.local hardening/sshd_config.d/10-hardening.conf:/etc/ssh/sshd_config.d/10-hardening.conf hardening/firewall/sdwa5-firewall.sh:/usr/local/sbin/sdwa5-firewall.sh hardening/firewall/sdwa5-firewall.service:/etc/systemd/system/sdwa5-firewall.service hardening/netplan/60-ipv6.yaml:/etc/netplan/60-ipv6.yaml hardening/cloud-init/99-disable-network-config.cfg:/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg}"
DATABASE_BACKUP_CONTAINERS="${DATABASE_BACKUP_CONTAINERS:-dolibarr_db shopware chimodiazz_shopware paperless_sdwa5_db paperless_home_db}"
RESTORE_CHECK="${RESTORE_CHECK:-$MONITORING_DIR/database-restore-check.sh}"

PORT_TIMEOUT="${PORT_TIMEOUT:-3}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-2}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-15}"

WORK_DIR=""
CRIT_COUNT=0
WARN_COUNT=0
OK_COUNT=0

cleanup() {
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

usage() {
    cat <<'USAGE'
security-recheck.sh - repeat the SdWa5 exposure, firewall and isolation checks

  security-recheck.sh              external probes here, host probes over ssh
  security-recheck.sh --external   external probes only
  security-recheck.sh --host       host probes only (root on the VPS)
  security-recheck.sh --restore    also run the SQL restore checks on the host
  security-recheck.sh --strict     a WARN also fails the run
  security-recheck.sh --help       this text

External: open ports on IPv4 and IPv6, HTTP/3, sites answering 200, no Server or
X-Powered-By header, HSTS, blocked paths including bypass variants.
Host: INPUT and DOCKER-USER on both families, cross-application isolation, the
container gateways, database egress, secrets in container environments, the
dockware listeners that must be closed, deployed revision and config copies.

Read-only. See docs/monitoring.md for the variables and the pass conditions.
USAGE
}

# emit KEY CHECK-OUTPUT
#
# One "key<TAB>status<TAB>message" line per call, counted. A status that is not OK, WARN or CRIT
# becomes a CRIT, the same normalisation vps-health.sh does, so a broken check cannot pass by
# printing something unexpected.
emit() {
    local key="$1" out="$2" status message

    status="${out%%$'\t'*}"
    message="${out#*$'\t'}"
    message="$(printf '%s' "$message" | tr '\n\t' '  ' | sed 's/  */ /g; s/ *$//')"

    case "$status" in
        OK|WARN|CRIT) ;;
        *)
            message="malformed check output: ${status} ${message}"
            status="CRIT"
            ;;
    esac

    case "$status" in
        OK) OK_COUNT=$((OK_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        CRIT) CRIT_COUNT=$((CRIT_COUNT + 1)) ;;
    esac

    printf '%s\t%s\t%s\n' "$key" "$status" "$message"
}

# in_list WORD LIST
in_list() {
    [[ " $2 " == *" $1 "* ]]
}

# ---------------------------------------------------------------------------
# External checks
# ---------------------------------------------------------------------------

# port_state FAMILY ADDRESS PORT
#
# open, refused or filtered. A DROP policy makes a closed port time out, so "refused" from the
# internet means something answers with a reset where the audit measured silence.
port_state() {
    local family="$1" address="$2" port="$3" err

    if err="$(nc "-$family" -z -v -w "$PORT_TIMEOUT" "$address" "$port" 2>&1)"; then
        echo open
    elif grep -qi 'refused' <<<"$err"; then
        echo refused
    else
        echo filtered
    fi
}

# check_ports FAMILY ADDRESS
#
# Every port runs in the background, so a family costs one timeout instead of 45.
check_ports() {
    local family="$1" address="$2" port state dir open=() refused=() unexpected=() missing=()

    dir="$WORK_DIR/ports$family"
    mkdir -p "$dir"
    for port in $EXTERNAL_TCP_PORTS; do
        port_state "$family" "$address" "$port" > "$dir/$port" &
    done
    wait

    for port in $EXTERNAL_TCP_PORTS; do
        state="$(cat "$dir/$port")"
        case "$state" in
            open) open+=("$port") ;;
            refused) refused+=("$port") ;;
        esac
    done
    for port in "${open[@]}"; do
        in_list "$port" "$EXPECTED_TCP_OPEN" || unexpected+=("$port")
    done
    for port in $EXPECTED_TCP_OPEN; do
        in_list "$port" "${open[*]}" || missing+=("$port")
    done

    # **A FAMILY WITH NOTHING OPEN IS MOST LIKELY THIS CLIENT, NOT THE HOST.** From a line without a
    # working IPv6 route every port times out, and that reads exactly like a host that drops
    # everything. The same picture had a real cause once (2026-10-16, IPv6 lost after the Debian 13
    # boot), so it is a warning that asks for a second vantage point rather than a pass.
    if (( ${#open[@]} == 0 )); then
        printf 'WARN\tno port answered over IPv%s from here, exposure not verified; check this client'"'"'s IPv%s path, then the host\n' "$family" "$family"
        return
    fi
    if (( ${#unexpected[@]} )); then
        printf 'CRIT\tunexpected open tcp port(s) %s on %s\n' "${unexpected[*]}" "$address"
        return
    fi
    if (( ${#missing[@]} )); then
        printf 'CRIT\texpected tcp port(s) %s do not answer on %s\n' "${missing[*]}" "$address"
        return
    fi
    if (( ${#refused[@]} )); then
        printf 'WARN\tonly %s open, but %s refused instead of timing out\n' "${open[*]}" "${refused[*]}"
        return
    fi
    printf 'OK\tonly %s open of %s probed tcp ports\n' "${open[*]}" "$(wc -w <<<"$EXTERNAL_TCP_PORTS")"
}

check_http3() {
    local version

    if ! curl -V 2>/dev/null | grep -qw 'HTTP3'; then
        printf 'WARN\tthis curl has no HTTP/3 support, udp 443 not verified\n'
        return
    fi
    version="$(curl --http3-only -sS -o /dev/null -w '%{http_version}' --max-time "$HTTP_TIMEOUT" "https://$HTTP3_SITE/" 2>/dev/null)"
    if [[ "$version" == 3 ]]; then
        printf 'OK\t%s answers over HTTP/3\n' "$HTTP3_SITE"
    else
        printf 'CRIT\t%s does not answer over HTTP/3 (got %s)\n' "$HTTP3_SITE" "${version:-nothing}"
    fi
}

# fetch URL
#
# Sets FETCH_STATUS, FETCH_HEADERS (a file) and FETCH_BODY (a file). --path-as-is keeps curl from
# normalising dot segments itself, which would hide exactly the variants worth probing.
fetch() {
    FETCH_HEADERS="$WORK_DIR/headers"
    FETCH_BODY="$WORK_DIR/body"
    : > "$FETCH_HEADERS"
    : > "$FETCH_BODY"
    FETCH_STATUS="$(curl -sS -g --path-as-is -D "$FETCH_HEADERS" -o "$FETCH_BODY" -w '%{http_code}' \
        --max-time "$HTTP_TIMEOUT" "$1" 2>/dev/null)"
    [[ -n "$FETCH_STATUS" ]] || FETCH_STATUS=000
}

has_header() {
    grep -qi "^$1:" "$FETCH_HEADERS"
}

# check_site SITE
#
# 200 on / and none of the headers hide_server_headers strips.
check_site() {
    local site="$1" leaked=()

    fetch "https://$site/"
    if [[ "$FETCH_STATUS" != 200 ]]; then
        printf 'CRIT\t%s returned %s\n' "$site" "$FETCH_STATUS"
        return
    fi
    has_header server && leaked+=("Server")
    has_header x-powered-by && leaked+=("X-Powered-By")
    if (( ${#leaked[@]} )); then
        printf 'CRIT\t%s answers 200 but sends %s\n' "$site" "${leaked[*]}"
        return
    fi
    printf 'OK\t%s answers 200 without Server or X-Powered-By\n' "$site"
}

check_hsts() {
    local site="$1" age

    fetch "https://$site/"
    age="$(grep -i '^strict-transport-security:' "$FETCH_HEADERS" | grep -oiE 'max-age=[0-9]+' | head -1 | cut -d= -f2)"
    if [[ -z "$age" ]]; then
        printf 'CRIT\t%s sends no HSTS header\n' "$site"
    elif (( age < HSTS_MIN_AGE )); then
        printf 'CRIT\t%s HSTS max-age %s is below %s\n' "$site" "$age" "$HSTS_MIN_AGE"
    else
        printf 'OK\t%s HSTS max-age %s\n' "$site" "$age"
    fi
}

# percent_encode TEXT
percent_encode() {
    local text="$1" out="" i

    for (( i = 0; i < ${#text}; i++ )); do
        out+="$(printf '%%%02x' "'${text:i:1}")"
    done
    printf '%s' "$out"
}

# path_variants PATH
#
# The spellings a matcher has to treat like the path itself: trailing slash and suffixes, a
# doubled slash, case changes, percent-encoding and dot segments. Generated rather than listed, so
# a new blocked path gets the same coverage. A double-encoded path (%2561) is left out on purpose:
# it is a different path to Caddy and reaches the upstream, which answers it with its own 404.
path_variants() {
    local path="$1" parent last first rest

    parent="${path%/*}"
    last="${path##*/}"
    first="${last:0:1}"
    rest="${last:1}"

    {
        printf '%s\n' "$path" "$path/" "$path/x" "$path?x=1" "/$path" "${path^^}"
        printf '%s\n' "$parent/${first^^}$rest"
        printf '%s\n' "$parent/$(percent_encode "$first")$rest"
        printf '%s\n' "$parent/$(percent_encode "$last")"
        printf '%s\n' "/.$path" "/x/..$path" "$parent/./$last"
    } | sort -u
}

# check_blocked SITE PATH
#
# OK for Caddy's own 404, WARN for an upstream 404 (the matcher missed it, the application happened
# to refuse it), CRIT for anything else, because then the blocked tool answered.
check_blocked() {
    local site="$1" path="$2" variant total=0 caddy=0 upstream=() crit=()

    while IFS= read -r variant; do
        total=$((total + 1))
        fetch "https://$site$variant"
        if [[ "$FETCH_STATUS" == 404 && "$(cat "$FETCH_BODY")" == "$CADDY_404_BODY" ]]; then
            caddy=$((caddy + 1))
        elif [[ "$FETCH_STATUS" == 404 ]]; then
            upstream+=("$variant")
        else
            crit+=("$variant ($FETCH_STATUS)")
        fi
    done < <(path_variants "$path")

    if (( ${#crit[@]} )); then
        printf 'CRIT\t%s of %s variants were not blocked: %s\n' "${#crit[@]}" "$total" "${crit[*]}"
    elif (( ${#upstream[@]} )); then
        printf 'WARN\t%s of %s variants reached the upstream, which answered 404: %s\n' "${#upstream[@]}" "$total" "${upstream[*]}"
    else
        printf 'OK\tall %s variants answered by Caddy with 404\n' "$caddy"
    fi
}

run_external() {
    local site pair

    emit "ports:v4" "$(check_ports 4 "$RECHECK_TARGET_V4")"
    if [[ -n "$RECHECK_TARGET_V6" ]]; then
        emit "ports:v6" "$(check_ports 6 "$RECHECK_TARGET_V6")"
    fi
    emit "http3:$HTTP3_SITE" "$(check_http3)"
    for site in $RECHECK_SITES; do
        emit "site:$site" "$(check_site "$site")"
    done
    for site in $HSTS_SITES; do
        emit "hsts:$site" "$(check_hsts "$site")"
    done
    for pair in $BLOCKED_PATHS; do
        emit "blocked:${pair%%=*}${pair#*=}" "$(check_blocked "${pair%%=*}" "${pair#*=}")"
    done
}

# ---------------------------------------------------------------------------
# Host checks
# ---------------------------------------------------------------------------

# check_firewall_family iptables|ip6tables
check_firewall_family() {
    local tool="$1" rules first port problems=()

    rules="$("$tool" -S INPUT 2>/dev/null)"
    if [[ -z "$rules" ]]; then
        printf 'CRIT\tcould not read the %s INPUT chain\n' "$tool"
        return
    fi

    grep -q '^-P INPUT DROP' <<<"$rules" || problems+=("INPUT policy is not DROP")
    grep -q -- '-j f2b-sshd' <<<"$rules" || problems+=("no fail2ban jump")
    for port in $FIREWALL_PORTS; do
        grep -qE -- "-p tcp .*--dport $port .*-j ACCEPT" <<<"$rules" || problems+=("tcp $port not accepted")
    done
    for port in $FIREWALL_UDP_PORTS; do
        grep -qE -- "-p udp .*--dport $port .*-j ACCEPT" <<<"$rules" || problems+=("udp $port not accepted")
    done
    if (( ${#problems[@]} )); then
        printf 'CRIT\t%s\n' "$(IFS=';'; echo "${problems[*]}")"
        return
    fi

    # fail2ban inserts its jump at the head of INPUT. Behind an ACCEPT for port 22 it bans nothing.
    first="$(grep -m1 '^-A INPUT' <<<"$rules")"
    if [[ "$first" != *"-j f2b-sshd"* ]]; then
        printf 'WARN\tthe fail2ban jump is not the first INPUT rule\n'
        return
    fi
    printf 'OK\tINPUT DROP, fail2ban jump first, tcp %s and udp %s accepted\n' "$FIREWALL_PORTS" "$FIREWALL_UDP_PORTS"
}

# A published container port is DNAT'd and traverses FORWARD, so INPUT does not see it.
check_docker_user() {
    local rules

    rules="$(iptables -S DOCKER-USER 2>/dev/null)"
    if grep -q -- "-i $WAN_INTERFACE -j DROP" <<<"$rules"; then
        printf 'OK\tDOCKER-USER drops what arrives on %s\n' "$WAN_INTERFACE"
    else
        printf 'CRIT\tDOCKER-USER has no drop for %s, published container ports are unfiltered\n' "$WAN_INTERFACE"
    fi
}

# app_of CONTAINER
app_of() {
    local pair members

    for pair in $ISOLATION_APPS; do
        members=",${pair#*=},"
        if [[ "$members" == *",$1,"* ]]; then
            printf '%s' "${pair%%=*}"
            return
        fi
    done
}

all_containers() {
    local pair
    for pair in $ISOLATION_APPS; do
        tr ',' '\n' <<<"${pair#*=}"
    done
}

container_ips() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" 2>/dev/null
}

container_gateways() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.Gateway}} {{end}}' "$1" 2>/dev/null \
        | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
}

# listening_ports CONTAINER
#
# Every TCP port the container listens on outside loopback, read from /proc so it needs no ss or
# netstat in the image. The address column is little-endian hex, so a v4 loopback address ends in
# 7F and v6 loopback is ...01000000. Docker's embedded DNS (127.0.0.11) falls out the same way.
listening_ports() {
    docker exec "$1" cat /proc/net/tcp /proc/net/tcp6 2>/dev/null \
        | awk '$4 == "0A" { print $2 }' \
        | while IFS=: read -r address port; do
            [[ "$address" == *7F || "$address" == 00000000000000000000000001000000 ]] && continue
            printf '%d\n' "$((16#$port))"
        done | sort -nu
}

# The probe that runs inside a container. bash's /dev/tcp needs no nc in the image; timeout tells
# a silent drop (124) from a refusal.
# shellcheck disable=SC2016
PROBE_SNIPPET='t=$1; shift
for target in "$@"; do
    (
        timeout "$t" bash -c ": </dev/tcp/${target%:*}/${target##*:}" 2>/dev/null
        rc=$?
        if [ "$rc" -eq 0 ]; then echo "$target open"
        elif [ "$rc" -eq 124 ]; then echo "$target filtered"
        else echo "$target refused"; fi
    ) &
done
wait'

# probe_from CONTAINER HOST:PORT...
probe_from() {
    local source="$1"
    shift
    docker exec "$source" bash -c "$PROBE_SNIPPET" probe "$PROBE_TIMEOUT" "$@" 2>/dev/null
}

# check_isolation SOURCE
#
# Targets every listening port on every address of every container outside the source's own
# application, plus the paths that must stay open. Enumerated from /proc, so a new listener is
# probed without anybody adding it here.
check_isolation() {
    local source="$1" app container ip port entry target expected=() targets=() open=() missing=() leaks=()
    local -A name_of=()

    if [[ "$(docker inspect -f '{{.State.Running}}' "$source" 2>/dev/null)" != true ]]; then
        printf 'CRIT\t%s is not running, isolation not measured\n' "$source"
        return
    fi
    app="$(app_of "$source")"

    for entry in $ISOLATION_EXPECT_OPEN; do
        [[ "${entry%%>*}" == "$source" ]] || continue
        target="${entry#*>}"
        for ip in $(container_ips "${target%:*}"); do
            targets+=("$ip:${target##*:}")
            expected+=("$ip:${target##*:}")
            name_of["$ip:${target##*:}"]="$target"
        done
    done

    while IFS= read -r container; do
        [[ -n "$container" && "$(app_of "$container")" != "$app" ]] || continue
        [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == true ]] || continue
        for port in $(listening_ports "$container"); do
            for ip in $(container_ips "$container"); do
                targets+=("$ip:$port")
                name_of["$ip:$port"]="$container:$port"
            done
        done
    done < <(all_containers)

    if (( ${#targets[@]} == 0 )); then
        printf 'CRIT\tno target found to probe from %s\n' "$source"
        return
    fi

    while read -r target state; do
        [[ "$state" == open ]] && open+=("$target")
    done < <(probe_from "$source" "${targets[@]}")

    for target in "${open[@]}"; do
        in_list "$target" "${expected[*]}" || leaks+=("${name_of[$target]:-$target}")
    done
    for target in "${expected[@]}"; do
        in_list "$target" "${open[*]}" || missing+=("${name_of[$target]:-$target}")
    done

    if (( ${#leaks[@]} )); then
        printf 'CRIT\t%s reaches %s\n' "$source" "${leaks[*]}"
    elif (( ${#missing[@]} )); then
        printf 'CRIT\t%s cannot reach %s, which it needs\n' "$source" "${missing[*]}"
    else
        printf 'OK\t%s reaches nothing outside %s among %s probed address:port pairs\n' "$source" "$app" "${#targets[@]}"
    fi
}

# secret_names
#
# Reads NAME=VALUE lines and prints the names that look like credentials, space separated, never a
# value. The name rule is the one monitoring/lib.sh's env_key_is_secret applies. A value that is
# empty, a *_FILE path, dockware's `not-set` placeholder or an argon2 PHC hash (Vaultwarden's
# ADMIN_TOKEN) is not a secret.
secret_names() {
    awk -F= '{ k = $1; v = substr($0, length(k) + 2) }
        k ~ /_FILE$/ || v == "" || v == "not-set" || v ~ /^\$argon2/ { next }
        k ~ /(PASS|TOKEN|SECRET)/ || k ~ /_KEY$/ { print k }' | sort -u | paste -sd' ' -
}

# Every process environment in the container, one NAME=VALUE per line. A process that ends while the
# loop runs is skipped rather than failing the read.
# shellcheck disable=SC2016
ENVIRON_SNIPPET='for f in /proc/[0-9]*/environ; do tr "\000" "\n" < "$f" 2>/dev/null; echo; done'

# check_env_exposure CONTAINER
#
# Since SEC-11 the stack's secrets reach the containers as files under /run/sdwa5-secrets, so docker
# inspect must show none of them. A value there is a WARN, because anyone who can inspect containers
# reads it and it lands in every config dump. The processes inside can still carry values: MariaDB's
# file_env and Paperless's s6 init-env-file export what they read from a *_FILE. Those names are
# listed in the OK message, so that residual stays visible instead of passing silently.
check_env_exposure() {
    local container="$1" config process

    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true ]]; then
        printf 'OK	%s is not running, no environment to read
' "$container"
        return
    fi
    config="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null | secret_names)"
    if ! docker exec --user 0 "$container" sh -c 'test -r /proc/1/environ' 2>/dev/null; then
        printf 'WARN	%s: process environments not readable%s
' "$container" "${config:+; docker inspect shows secret values for $config}"
        return
    fi
    process="$(docker exec --user 0 "$container" sh -c "$ENVIRON_SNIPPET" 2>/dev/null | secret_names)"

    if [[ -n "$config" ]]; then
        printf 'WARN	docker inspect shows secret values for %s%s
' "$config" "${process:+; process environment: $process}"
    elif [[ -n "$process" ]]; then
        printf 'OK	no secret in docker inspect; process environment still carries %s
' "$process"
    else
        printf 'OK	no secret in docker inspect or in any process environment
'
    fi
}

# check_closed_listeners CONTAINER PORTS
#
# PORTS is comma separated. Read from /proc like the isolation check, so it needs nothing in the image.
check_closed_listeners() {
    local container="$1" ports="${2//,/ }" port open=()

    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true ]]; then
        printf 'OK	%s is not running
' "$container"
        return
    fi
    for port in $(listening_ports "$container"); do
        in_list "$port" "$ports" && open+=("$port")
    done
    if (( ${#open[@]} )); then
        printf 'WARN	%s listens on %s, which its boot hook should have closed
' "$container" "${open[*]}"
    else
        printf 'OK	none of %s listens
' "$ports"
    fi
}

# check_gateway SOURCE
#
# The host as a container sees it: only what the internet sees, nothing of the loopback publishes.
check_gateway() {
    local source="$1" gateway port targets=() open=() bad=() missing=() target state

    for gateway in $(container_gateways "$source"); do
        for port in $GATEWAY_OPEN $GATEWAY_CLOSED; do
            targets+=("$gateway:$port")
        done
    done
    if (( ${#targets[@]} == 0 )); then
        printf 'OK\t%s has no gateway, so it cannot reach the host\n' "$source"
        return
    fi

    while read -r target state; do
        [[ "$state" == open ]] && open+=("$target")
    done < <(probe_from "$source" "${targets[@]}")

    for gateway in $(container_gateways "$source"); do
        for port in $GATEWAY_CLOSED; do
            in_list "$gateway:$port" "${open[*]}" && bad+=("$gateway:$port")
        done
        for port in $GATEWAY_OPEN; do
            in_list "$gateway:$port" "${open[*]}" || missing+=("$gateway:$port")
        done
    done

    if (( ${#bad[@]} )); then
        printf 'CRIT\t%s reaches the host on %s\n' "$source" "${bad[*]}"
    elif (( ${#missing[@]} )); then
        printf 'WARN\t%s does not reach the host on %s\n' "$source" "${missing[*]}"
    else
        printf 'OK\t%s reaches the host on %s only\n' "$source" "$GATEWAY_OPEN"
    fi
}

check_egress() {
    local container="$1" target state open=()

    # shellcheck disable=SC2086
    while read -r target state; do
        [[ "$state" == open ]] && open+=("$target")
    done < <(probe_from "$container" $EGRESS_PROBES)

    if (( ${#open[@]} )); then
        printf 'CRIT\t%s reaches the internet: %s\n' "$container" "${open[*]}"
    else
        printf 'OK\t%s has no egress to %s\n' "$container" "$EGRESS_PROBES"
    fi
}

# Read-only: ls-remote, never fetch, so the checkout is exactly as it was found.
#
# A lag is a WARN rather than a CRIT. Without fetching, the script cannot tell a security fix that is
# not deployed from a TODO.md commit, and the first live run (2026-10-16) found the latter. The
# exposure itself is measured by the other checks.
check_revision() {
    local head remote changed

    head="$(git -C "$GIT_CHECKOUT_DIR" rev-parse HEAD 2>/dev/null)"
    if [[ -z "$head" ]]; then
        printf 'CRIT\t%s is not a git checkout\n' "$GIT_CHECKOUT_DIR"
        return
    fi
    remote="$(timeout 20 git -C "$GIT_CHECKOUT_DIR" ls-remote origin "refs/heads/$GIT_BRANCH" 2>/dev/null | cut -f1)"
    changed="$(git -C "$GIT_CHECKOUT_DIR" status --porcelain --untracked-files=no 2>/dev/null | wc -l)"

    if [[ -z "$remote" ]]; then
        printf 'WARN\tdeployed %s, origin/%s not reachable\n' "${head:0:7}" "$GIT_BRANCH"
    elif [[ "$head" != "$remote" ]]; then
        printf 'WARN\tdeployed %s differs from origin/%s %s\n' "${head:0:7}" "$GIT_BRANCH" "${remote:0:7}"
    elif (( changed )); then
        printf 'WARN\tdeployed %s equals origin/%s, but %s tracked file(s) are modified\n' "${head:0:7}" "$GIT_BRANCH" "$changed"
    else
        printf 'OK\tdeployed %s equals origin/%s, no tracked change\n' "${head:0:7}" "$GIT_BRANCH"
    fi
}

check_deployed_files() {
    local pair source target drift=()

    for pair in $DEPLOYED_FILES; do
        source="$GIT_CHECKOUT_DIR/${pair%%:*}"
        target="${pair#*:}"
        cmp -s "$source" "$target" || drift+=("$target")
    done
    if (( ${#drift[@]} )); then
        printf 'WARN\tdiffers from the checkout or missing: %s\n' "${drift[*]}"
    else
        printf 'OK\tall %s deployed config files equal the checkout\n' "$(wc -w <<<"$DEPLOYED_FILES")"
    fi
}

check_restore() {
    local container="$1" out

    if out="$("$RESTORE_CHECK" "$container" 2>/dev/null)"; then
        printf 'OK\t%s\n' "$(tail -n1 <<<"$out")"
    else
        printf 'CRIT\tthe restore check of %s failed\n' "$container"
    fi
}

run_host() {
    local restore="$1" source container entry

    emit "firewall:v4" "$(check_firewall_family iptables)"
    emit "firewall:v6" "$(check_firewall_family ip6tables)"
    emit "firewall:docker-user" "$(check_docker_user)"
    for source in $ISOLATION_SOURCES; do
        emit "isolation:$source" "$(check_isolation "$source")"
        emit "gateway:$source" "$(check_gateway "$source")"
    done
    for container in $NO_EGRESS_CONTAINERS; do
        emit "egress:$container" "$(check_egress "$container")"
    done
    while IFS= read -r container; do
        [[ -n "$container" ]] && emit "env:$container" "$(check_env_exposure "$container")"
    done < <(all_containers)
    for entry in $CLOSED_LISTENERS; do
        emit "listeners:${entry%%:*}" "$(check_closed_listeners "${entry%%:*}" "${entry#*:}")"
    done
    emit "revision:$GIT_BRANCH" "$(check_revision)"
    emit "deployed:files" "$(check_deployed_files)"
    if (( restore )); then
        for container in $DATABASE_BACKUP_CONTAINERS; do
            emit "restore:$container" "$(check_restore "$container")"
        done
    fi
}

# run_remote RESTORE
#
# The host part over ssh. Its lines are already "key<TAB>status<TAB>message"; each is checked and
# counted again here, so a truncated or garbled remote run cannot read as a pass.
run_remote() {
    local restore="$1" out line complete=0 args=(--host)

    (( restore )) && args+=(--restore)
    if ! out="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$RECHECK_SSH_HOST" "$RECHECK_REMOTE_SCRIPT" "${args[@]}" 2>/dev/null)" \
        && [[ -z "$out" ]]; then
        emit "host:ssh" "$(printf 'CRIT\tthe host part did not run on %s' "$RECHECK_SSH_HOST")"
        return
    fi
    if [[ -z "$out" ]]; then
        emit "host:ssh" "$(printf 'CRIT\tthe host part printed nothing')"
        return
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "${line%%$'\t'*}" == host:complete ]]; then
            complete=1
        elif [[ "$line" == *$'\t'*$'\t'* ]]; then
            emit "${line%%$'\t'*}" "${line#*$'\t'}"
        else
            emit "host:output" "$line"
        fi
    done <<<"$out"
    (( complete )) || emit "host:complete" "$(printf 'CRIT\tthe host part ended before its last check')"
}

main() {
    local mode=both restore=0 strict=0 arg

    for arg in "$@"; do
        case "$arg" in
            --external) mode=external ;;
            --host) mode=host ;;
            --restore) restore=1 ;;
            --strict) strict=1 ;;
            -h|--help) usage; return 0 ;;
            *) usage >&2; return 2 ;;
        esac
    done

    WORK_DIR="$(mktemp -d)"

    case "$mode" in
        external) run_external ;;
        host)
            run_host "$restore"
            # The workstation side requires this line, so a run cut short reads as a failure.
            emit "host:complete" "$(printf 'OK\thost part finished')"
            ;;
        both)
            run_external
            run_remote "$restore"
            ;;
    esac

    printf '%s OK, %s WARN, %s CRIT\n' "$OK_COUNT" "$WARN_COUNT" "$CRIT_COUNT" >&2
    (( CRIT_COUNT == 0 )) || return 1
    (( strict && WARN_COUNT )) && return 1
    return 0
}

main "$@"
