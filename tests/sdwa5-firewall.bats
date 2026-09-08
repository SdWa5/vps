#!/usr/bin/env bats
# Tests for hardening/firewall/sdwa5-firewall.sh
#
# The script writes firewall rules, so every test runs it against the iptables
# stub and asserts what it tried to write rather than what a kernel did.

load test_helper

setup() {
    common_setup
    export STUB_IPT_LOG="$BATS_TEST_TMPDIR/iptables.log"
    : > "$STUB_IPT_LOG"
}

firewall() {
    run "$REPO_ROOT/hardening/firewall/sdwa5-firewall.sh"
}

wrote() {
    grep -qF -- "$1" "$STUB_IPT_LOG"
}

@test "the INPUT chain is flushed and rebuilt with a DROP policy" {
    firewall
    [ "$status" -eq 0 ]
    wrote "iptables -F INPUT"
    wrote "iptables -P INPUT DROP"
}

@test "the service ports are accepted" {
    firewall
    wrote "--dport 22 -j ACCEPT"
    wrote "--dport 80 -j ACCEPT"
    wrote "--dport 443 -j ACCEPT"
}

@test "every discovered bridge is accepted on INPUT" {
    STUB_BRIDGES="docker0 br-abc123" firewall
    wrote "-i docker0 -j ACCEPT"
    wrote "-i br-abc123 -j ACCEPT"
}

# --- DOCKER-USER -----------------------------------------------------------

@test "DOCKER-USER is flushed and given a DROP for the outside world" {
    firewall
    wrote "iptables -F DOCKER-USER"
    wrote "-A DOCKER-USER -i eth0 -j DROP"
}

@test "DOCKER-USER keeps minecraft reachable on both protocols" {
    firewall
    wrote "-A DOCKER-USER -i eth0 -p tcp --dport 25565 -j RETURN"
    wrote "-A DOCKER-USER -i eth0 -p udp --dport 25565 -j RETURN"
}

@test "DOCKER-USER returns container egress rather than accepting it" {
    # RETURN hands the packet back so Docker's own isolation chains still judge
    # it. ACCEPT would skip them and switch off isolation between projects.
    STUB_BRIDGES="docker0" firewall
    wrote "-A DOCKER-USER -i docker0 -j RETURN"
    ! wrote "-A DOCKER-USER -i docker0 -j ACCEPT"
}

@test "DOCKER-USER ends with a RETURN so Docker's chains still run" {
    firewall
    wrote "-A DOCKER-USER -j RETURN"
}

@test "the external interface comes from the default route" {
    STUB_WAN="ens3" firewall
    wrote "-A DOCKER-USER -i ens3 -j DROP"
    ! wrote "-A DOCKER-USER -i eth0 -j DROP"
}

# --- the fail2ban jump -----------------------------------------------------

# Regression for 2026-09-08. Flushing INPUT removes the jump fail2ban puts at
# its head, and the unit's ExecStartPost restart of fail2ban did not bring it
# back, measured over 30 seconds. So every firewall restart and every boot
# silently switched off SSH brute-force filtering.
@test "the fail2ban jump is re-added when its chain exists" {
    STUB_IPT_HAVE="-C f2b-sshd -j RETURN" firewall
    wrote "-I INPUT -p tcp -m multiport --dports ssh -j f2b-sshd"
}

@test "the fail2ban jump is not touched when its chain does not exist" {
    # Creating f2b-sshd is fail2ban's job, and a jump to a missing chain fails.
    STUB_IPT_HAVE="" firewall
    ! wrote "-j f2b-sshd"
}

@test "an existing fail2ban jump is not inserted twice" {
    STUB_IPT_HAVE="-C f2b-sshd -j RETURN
-C INPUT -p tcp -m multiport --dports ssh -j f2b-sshd" firewall
    ! wrote "-I INPUT -p tcp -m multiport --dports ssh -j f2b-sshd"
}

# --- IPv6 ------------------------------------------------------------------

@test "IPv6 INPUT gets the same treatment" {
    firewall
    wrote "ip6tables -F INPUT"
    wrote "ip6tables -P INPUT DROP"
    wrote "ip6tables -A INPUT -p ipv6-icmp -j ACCEPT"
}

@test "IPv6 gets no DOCKER-USER rules, because Docker publishes nothing over v6" {
    # Measured 2026-09-08: zero Docker rules in ip6tables, zero v6 DNAT, both
    # bridges link-local only, no daemon.json. Writing v6 rules would defend an
    # empty path, and ip6tables cannot address that chain here anyway.
    firewall
    ! wrote "ip6tables -A DOCKER-USER"
}
