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
# fail2ban inserts its jump at the head of INPUT when it starts. The unit that
# runs this is ordered Before=fail2ban.service so that jump survives.
set -e

BRIDGES=$(ip -o link show type bridge | awk '{print $2}' | tr -d ':')
# The interface the default route leaves by, so "from outside" is derived rather
# than hardcoded. Measured 2026-09-08 as eth0.
WAN=$(ip -o -4 route show default | awk '{print $5}' | head -1)

iptables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p icmp -j ACCEPT
for bridge in $BRIDGES; do
    iptables -A INPUT -i "$bridge" -j ACCEPT
done
iptables -A INPUT -p tcp --dport 22  -j ACCEPT
iptables -A INPUT -p tcp --dport 80  -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
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
# no IPv6 publishing on this host: ip6tables holds zero Docker rules, the v6 nat
# table holds zero DNAT entries, both bridges carry only a link-local fe80::
# address, and there is no /etc/docker/daemon.json enabling ipv6 or ip6tables.
# So there is no v6 path to a container to filter. Enabling Docker's IPv6 would
# change that, and then this needs a v6 counterpart written with nft, because
# ip6tables reports the v6 DOCKER-USER chain as incompatible with its compat
# layer.

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
ip6tables -P INPUT DROP
