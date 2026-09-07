#!/bin/bash
# Default-deny INPUT for the SdWa5 VPS, IPv4 and IPv6.
#
# It rewrites the INPUT chain and nothing else. Docker owns DOCKER, DOCKER-USER,
# DOCKER-ISOLATION and its FORWARD rules, and rebuilds them at its own start, so
# a full iptables-restore would replay stale copies of them at boot. This script
# is therefore idempotent by flushing only INPUT and appending its own rules.
#
# fail2ban inserts its jump at the head of INPUT when it starts. The unit that
# runs this is ordered Before=fail2ban.service so that jump survives.
set -e

BRIDGES=$(ip -o link show type bridge | awk '{print $2}' | tr -d ':')

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
