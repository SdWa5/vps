#!/usr/bin/env bash
#
# SdWa5 IPv6 reachability log (SEC-28).
#
# IPv6 on this host drops out for seconds to minutes and recovers on its own, while IPv4 and the
# gateway's neighbour entry look fine (TODO.md #7.3). Contabo needs timestamps and a log before a
# ticket makes sense, so this runs every minute from /etc/cron.d/ipv6-watch for about a day and
# appends one line per run. It is temporary and is removed once the ticket is filed.
#
# Each line: time, every v6 target, the gateway's neighbour state, the v4 control. A probe is the
# round trip in ms of the first reply, or "fail". The gateway itself is not pinged, because neither
# fe80::1 nor the next hop 2a02:c206::1eaf answers echo requests even while v6 works (measured
# 2026-10-17).
#
#   2026-10-17T18:01:00+02:00 2001:4860:4860::8888=4.1 2606:4700:4700::1111=fail neigh=REACHABLE v4=3.4
#
# Environment overrides:
#   IPV6_WATCH_TARGETS   space-separated external v6 addresses
#   IPV6_WATCH_GATEWAY   link-local v6 gateway whose neighbour entry is read, default fe80::1
#   IPV6_WATCH_IFACE     interface the gateway sits on, default eth0
#   IPV6_WATCH_V4        IPv4 control address, default 1.1.1.1
#   IPV6_WATCH_LOG       log file, default /var/log/sdwa5-ipv6.log

set -uo pipefail

IPV6_WATCH_TARGETS="${IPV6_WATCH_TARGETS:-2001:4860:4860::8888 2606:4700:4700::1111}"
IPV6_WATCH_GATEWAY="${IPV6_WATCH_GATEWAY:-fe80::1}"
IPV6_WATCH_IFACE="${IPV6_WATCH_IFACE:-eth0}"
IPV6_WATCH_V4="${IPV6_WATCH_V4:-1.1.1.1}"
IPV6_WATCH_LOG="${IPV6_WATCH_LOG:-/var/log/sdwa5-ipv6.log}"

# Two echo requests, and one reply is enough. A single request logged a false "fail" on the first
# live run while neighbour discovery was in PROBE. Each probe takes ca. 3 s, so a run stays well
# inside its minute. $1 is -4 or -6, $2 the target.
probe() {
    local rtt
    rtt="$(ping "$1" -n -c 2 -W 2 "$2" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n 1)"
    printf '%s' "${rtt:-fail}"
}

main() {
    local line target state
    line="$(date -Iseconds)"
    for target in $IPV6_WATCH_TARGETS; do
        line+=" $target=$(probe -6 "$target")"
    done
    state="$(ip -6 neigh show "$IPV6_WATCH_GATEWAY" dev "$IPV6_WATCH_IFACE" 2>/dev/null | awk '{print $NF}')"
    line+=" neigh=${state:-none}"
    line+=" v4=$(probe -4 "$IPV6_WATCH_V4")"
    printf '%s\n' "$line" >> "$IPV6_WATCH_LOG"
}

main "$@"
