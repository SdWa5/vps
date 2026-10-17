#!/usr/bin/env bats
# Tests for monitoring/ipv6-watch.sh

load test_helper

setup() {
    common_setup
    export IPV6_WATCH_LOG="$BATS_TEST_TMPDIR/ipv6.log"
}

watch() { run "$REPO_ROOT/monitoring/ipv6-watch.sh"; }

@test "a healthy run appends one line with every probe" {
    watch
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$IPV6_WATCH_LOG")" -eq 1 ]
    [[ "$(cat "$IPV6_WATCH_LOG")" == *" 2001:4860:4860::8888=1.5 2606:4700:4700::1111=1.5 neigh=REACHABLE v4=1.5" ]]
}

@test "runs append rather than overwrite" {
    watch
    watch
    [ "$(wc -l < "$IPV6_WATCH_LOG")" -eq 2 ]
}

@test "a v6 outage with a reachable gateway entry is logged as such" {
    STUB_ICMP_DOWN="2001:4860:4860::8888 2606:4700:4700::1111" watch
    [[ "$(cat "$IPV6_WATCH_LOG")" == *"8888=fail 2606:4700:4700::1111=fail neigh=REACHABLE v4=1.5" ]]
}

@test "the gateway is not pinged, because it never answers echo" {
    watch
    [[ "$(cat "$IPV6_WATCH_LOG")" != *"gw="* ]]
}

@test "a missing neighbour entry reads none" {
    STUB_NEIGH_STATE="" watch
    [[ "$(cat "$IPV6_WATCH_LOG")" == *"neigh=none"* ]]
}

@test "the line starts with an ISO timestamp" {
    watch
    [[ "$(cat "$IPV6_WATCH_LOG")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9:]{5}\  ]]
}
