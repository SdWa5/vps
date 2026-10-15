#!/bin/bash
# Default-deny INPUT for the SdWa5 VPS, IPv4 and IPv6, plus DOCKER-USER.
#
# It rewrites INPUT and DOCKER-USER and nothing else. Docker owns DOCKER,
# DOCKER-ISOLATION and its FORWARD rules, and rebuilds them at its own start, so
# a full iptables-restore would replay stale copies of them at boot. This script
# is therefore idempotent by flushing only the two chains it owns and appending
# its own rules.
#
# DOCKER-USER is the exception Docker provides deliberately: it creates the chain
# empty, jumps to it from the head of FORWARD and never puts rules in it, so it
# is the operator's. Taking it is what makes a published container port
# filterable at all, because such a packet is DNAT'd and traverses FORWARD
# rather than INPUT, which is why an INPUT-only firewall could never see it.
#
# fail2ban's jump is re-added by this script rather than by fail2ban.
#
# Flushing INPUT removes the jump fail2ban puts at its head, and until
# 2026-09-08 this relied on the unit's ExecStartPost restarting fail2ban so that
# fail2ban would re-insert it. **That does not work.** Measured: after
# `systemctl restart sdwa5-firewall`, fail2ban restarts and logs "Server ready"
# and "Creating new jail 'sshd'", and 30 seconds later the jump is still absent.
# The same commands run by hand insert it without complaint, so the cause inside
# fail2ban is not established, only the effect is. The effect is what matters,
# because it means every firewall restart and every boot silently switched off
# SSH brute-force filtering while the chain still looked correct.
#
# So this script re-adds the jump itself, deterministically. It never touches
# the f2b-sshd chain, so existing bans in it survive a flush of INPUT untouched.
# The jump is only re-added when that chain exists, because creating it is
# fail2ban's job and a jump to a missing chain would fail.
#
# The same holds for IPv6. fail2ban creates the v6 f2b-sshd chain and its jump
# on the first IPv6 ban only, measured 2026-10-15 with a ban of 2001:db8::1.
# Until then this script re-added the IPv4 jump alone, so after any firewall
# restart an IPv6 ban would have landed in a chain that nothing jumps to.
set -e

# Puts fail2ban's jump back at the head of INPUT for one family. Inserted rather
# than appended, so it is judged before the blanket accept for port 22.
restore_fail2ban_jump() {
    local ipt="$1"
    if "$ipt" -C f2b-sshd -j RETURN >/dev/null 2>&1; then
        "$ipt" -C INPUT -p tcp -m multiport --dports ssh -j f2b-sshd >/dev/null 2>&1 \
            || "$ipt" -I INPUT -p tcp -m multiport --dports ssh -j f2b-sshd
    fi
}

BRIDGES=$(ip -o link show type bridge | awk '{print $2}' | tr -d ':')
# The interface the default route leaves by, so "from outside" is derived rather
# than hardcoded. Measured 2026-09-08 as eth0.
WAN=$(ip -o -4 route show default | awk '{print $5}' | head -1)

iptables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p icmp -j ACCEPT
# Containers get no blanket access to the host. Until 2026-10-15 every Docker
# bridge was accepted here, which let any container reach whatever the host
# serves on its gateway address. Measured before removing it: no container needs
# the host. Mail goes straight to smtp.gmail.com or to the shop's own in-container
# mailcatcher, DNS is Docker's embedded resolver, and Caddy talks to the
# containers rather than the other way round. A container still reaches 22, 80
# and 443 through the rules below, exactly as anyone on the internet does.
iptables -A INPUT -p tcp --dport 22  -j ACCEPT
iptables -A INPUT -p tcp --dport 80  -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT

restore_fail2ban_jump iptables

iptables -P INPUT DROP

# DOCKER-USER, which is where a published container port is actually filtered.
#
# Every rule here uses RETURN rather than ACCEPT for the traffic it allows.
# RETURN hands the packet back to FORWARD so Docker's own DOCKER-ISOLATION and
# DOCKER chains still get to judge it, while ACCEPT would skip them and quietly
# disable Docker's network isolation between compose projects.
#
# Ports named here are the container-side port after DNAT. For minecraft the
# host and container port are both 25565, so it reads the same either way.
iptables -N DOCKER-USER 2>/dev/null || true
iptables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
# Container egress and traffic between containers. Without this every outbound
# reply a container waits for is dropped, which breaks restic reaching Google
# Drive and every package install inside a container.
for bridge in $BRIDGES; do
    iptables -A DOCKER-USER -i "$bridge" -j RETURN
done
# minecraft publishes 25565 on all interfaces on purpose, so it stays reachable.
iptables -A DOCKER-USER -i "$WAN" -p tcp --dport 25565 -j RETURN
iptables -A DOCKER-USER -i "$WAN" -p udp --dport 25565 -j RETURN
# Anything else arriving from outside toward a container. This is what an
# accidental 0.0.0.0 publish runs into, which is the whole point of the chain.
iptables -A DOCKER-USER -i "$WAN" -j DROP
iptables -A DOCKER-USER -j RETURN

# There is no IPv6 half, and that is measured rather than skipped. Docker does
# no IPv6 publishing on this host: the v6 nat table holds zero DNAT entries, no
# Docker network has IPv6 enabled and net.ipv6.conf.all.forwarding is 0. So there
# is no v6 path to a container to filter. A port published on all interfaces,
# such as minecraft's, is served over IPv6 by docker-proxy per Docker's docs,
# which is a local socket judged by the v6 INPUT chain below. Not measured,
# because minecraft is profile-gated and not running. Since docker-ce 29 (2026-10-15) Docker's ip6tables default is on,
# so ip6tables holds its chain skeleton, 11 lines of `ip6tables -S`, and no DNAT.
# Enabling Docker's IPv6 would change that, and then this needs a v6 counterpart
# written with nft, because ip6tables reports the v6 DOCKER-USER chain as
# incompatible with its compat layer.

# ICMPv6 is accepted wholesale on purpose. Neighbour discovery and path MTU
# discovery both ride on it, and dropping it does not harden IPv6, it removes it.
ip6tables -F INPUT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -A INPUT -p tcp --dport 22  -j ACCEPT
ip6tables -A INPUT -p tcp --dport 80  -j ACCEPT
ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
ip6tables -A INPUT -p udp --dport 443 -j ACCEPT
restore_fail2ban_jump ip6tables
ip6tables -P INPUT DROP
