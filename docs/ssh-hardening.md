# SSH hardening

Applied 2026-09-07 after finding the box under a sustained password brute force. Everything here is
about host SSH access, not about any Docker service.

Deployable copies of both config files live in [`hardening/`](../hardening/) and are byte-identical
to what runs on the VPS.

## What was found

```
failed root logins, previous 24 h : 13,672
attempts per minute               : ~18, escalating to several hundred during the work
permitrootlogin                   : yes
passwordauthentication            : yes
firewall                          : iptables -P INPUT ACCEPT, no rules
fail2ban                          : not installed
authorized_keys for root          : one entry, a work key
```

Usernames the bots targeted, previous 24 h:

| Username | Attempts |
|---|---|
| root | 4,124 |
| ubuntu | 1,968 |
| admin | 306 |
| user, deploy, test, dev, debian | ~700 combined |

Three separate problems sat behind that.

**Password authentication was on and root could use it.** The only thing between the internet and
this host was the strength of the root password.

**A second account could be brute-forced to the same effect.** `admin`, uid 1000, is in the `sudo`
group with `(ALL : ALL) ALL`, had a password, and had no `authorized_keys` at all. Closing root
alone would have left it open, and the bots were already trying it 306 times a day.

**A work key held sole root on the private server.** `authorized_keys` contained exactly one entry,
an 8196-bit RSA key with the comment `sri@sri-VirtualBox`, which is a work key also used for
`github.com` and `git.myndc.de`. A work credential should not be the way into the private box that
carries the Vaultwarden vault, and the reverse exposure is just as unwanted.

**The flood was also a partial denial of service.** With `MaxStartups 10:30:100`, sshd starts
dropping new connections once ten sit in the pre-auth phase. Concurrency was at 30, the log showed
`drop connection #10 ... past MaxStartups`, and roughly one in three of our own connection attempts
was being reset.

## What changed

| | Before | After |
|---|---|---|
| `PasswordAuthentication` | yes | **no** |
| `PermitRootLogin` | yes | **prohibit-password** |
| `KbdInteractiveAuthentication` | no | no |
| `MaxStartups` | 10:30:100 | **30:50:200** |
| fail2ban | not installed | active, sshd jail, systemd backend |
| root `authorized_keys` | one work RSA key | one personal ed25519 key |

Result, measured over a clean window afterwards:

```
Failed password per minute : 0     (was ~180)
pre-auth concurrency       : 2     (was 30)
own connections succeeding : 5/5   (was ~2/3 dropped)
fail2ban banned            : 71 IPs within the first hour
```

Bots still connect and are refused, so `Invalid user` lines continue in the journal. They can no
longer guess anything.

## The trap that would have defeated this silently

`/etc/ssh/sshd_config.d/50-cloud-init.conf` contained exactly one line:

```
PasswordAuthentication yes
```

`/etc/ssh/sshd_config` already had `PasswordAuthentication no` at line 57, and it had no effect,
because the `Include /etc/ssh/sshd_config.d/*.conf` sits at **line 12** and sshd uses the **first**
occurrence of a keyword it encounters. cloud-init won.

Editing the main file therefore changes nothing, and `sshd -T` would keep reporting
`passwordauthentication yes` while the operator believed otherwise.

The fix is [`hardening/sshd_config.d/10-hardening.conf`](../hardening/sshd_config.d/10-hardening.conf),
which sorts **before** `50-cloud-init.conf` and so wins. `cloud-init.service` is still enabled, so it
will keep rewriting its own file on boot, and that no longer matters.

**Never assume a setting in `sshd_config` is live.** Read `sshd -T`, and read
`/etc/ssh/sshd_config.d/` before concluding anything.

## fail2ban

[`hardening/fail2ban/jail.local`](../hardening/fail2ban/jail.local)

The package installs but **fails to start** on this host with the Debian default:

```
ERROR Failed during configuration: Have not found any log file for sshd jail
```

sshd logs to journald only. rsyslog is not installed and `/var/log/auth.log` does not exist, so the
default backend `auto` finds nothing. `backend = systemd` is therefore set explicitly.

```
bantime  = 1h, doubling per repeat offence, capped at 1 week
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1
```

`ignoreip` deliberately holds only loopback. A home IP was whitelisted briefly during the work and
removed again, because a dynamic consumer address that later belongs to someone else would carry a
permanent exemption with it.

Note that fail2ban is rate limiting rather than a closed door. An attacker spreading four guesses
per source address never trips it. It is defence in depth behind key-only authentication, not a
substitute.

## Keys

| Key | Purpose | Passphrase |
|---|---|---|
| `id_ed25519_sdwa5` | the only entry in root's `authorized_keys` | yes |

Fingerprint `SHA256:3r0Dk1tFl8W/iHyFC6rsOFbQ1JznqEeP5+06iYug0mA`, comment
`stefanr@stefan-desktop sdwa5-vps personal 2026-09-07`.

This host is **not** exposed by the unprotected copies of the old keys that still sit on
stefan-notebook, because `id_rsa` was removed from `authorized_keys` here and `id_ed25519_sdwa5` does
not exist on that machine. Replacing the key rather than only adding a passphrase to it is what bought
that.

The private key is stored in Vaultwarden since 2026-09-08, as item
`00fceed1-965b-4857-9b91-2d371d0c6662`, uploaded by path and then downloaded again and compared
byte-for-byte against the file on disk. A second copy still belongs on the notebook.

Vaultwarden running on the very host this key unlocks looks circular, and that was the initial
reasoning for keeping it out. It does not hold up. If the key file is lost the vault is still up and
the key can be read back, and if Vaultwarden itself is down the Bitwarden clients cache the vault and
unlock offline, so the loop needs the server and every logged-in client to fail at once.

Two caveats do survive, and they are why the notebook copy stays on the list. A KDF or master password
change logs out every client, so for a while the vault exists only on the server. And a vault item
cannot be fetched from a rescue console, which is exactly where you sit when SSH is broken. The
Contabo console is therefore the break-glass rather than the vault.

Client-side detail, including the `~/.ssh/conf.d` layout and where each of the five keys is backed up,
is documented in `~/PhpstormProjects/ai/docs/ssh-keys.md`.

## Firewall

Added 2026-09-08. Deployable copies are
[`hardening/firewall/`](../hardening/firewall/) and
[`hardening/systemd/resolved.conf.d/`](../hardening/systemd/resolved.conf.d/), byte-identical to what
runs on the host.

### What was actually exposed, which is less than "no firewall" suggests

`iptables -P INPUT ACCEPT` with no rules sounds like every service is public. Measured before the
change, it was not:

```
0.0.0.0:22    sshd                needed
*:80, *:443   caddy, tcp and udp  needed
0.0.0.0:5355  systemd-resolved    LLMNR, not needed
127.0.0.1:25    exim4
127.0.0.1:2019  caddy admin API
127.0.0.1:8000  vaultwarden
127.0.0.1:8001  shopware
127.0.0.1:8002  dolibarr
127.0.0.1:8443  shopware tls
```

**Every Docker publish binds `127.0.0.1`.** The usual failure here is a container published on
`0.0.0.0`, which Docker inserts into its own `DOCKER` chain ahead of any host firewall and so exposes
regardless of what `INPUT` says. This compose file never did that, so the only unnecessary open port
was LLMNR.

That is why the firewall is defence in depth rather than a repair. It protects against the *next*
service that binds `0.0.0.0` by accident, not against a hole that was there.

### LLMNR

Link-local name resolution served nothing on a public VPS and was the one avoidable open port. It is
turned off at the source rather than filtered, which closes 5355 on TCP and UDP for both families.

### The rules

`INPUT` only, IPv4 and IPv6. Loopback, established and related, all ICMP, the Docker bridges, then
22, 80 and 443, then a `DROP` policy.

**`iptables-restore` is deliberately not used, and neither is `iptables-persistent`.** Both replace
every chain in the filter table, and Docker owns `DOCKER`, `DOCKER-USER`, `DOCKER-ISOLATION-*` and a
set of `FORWARD` rules that it rebuilds at its own start. Restoring a saved snapshot at boot would
replay stale copies of those, referring to bridges and subnets that may no longer exist.
[`sdwa5-firewall.sh`](../hardening/firewall/sdwa5-firewall.sh) therefore flushes `INPUT` alone and
appends its own rules, which makes it idempotent and leaves Docker's chains untouched.

**ICMPv6 is accepted wholesale on purpose.** Neighbour discovery and path MTU discovery both ride on
it. Dropping ICMPv6 does not harden IPv6, it removes it.

### fail2ban and the flush

fail2ban inserts its `f2b-sshd` jump at the head of `INPUT`, so flushing that chain removes it, and
SSH would then be unfiltered while still looking correct. Two things handle that:

- [`sdwa5-firewall.service`](../hardening/firewall/sdwa5-firewall.service) is ordered
  `Before=fail2ban.service`, so at boot fail2ban starts afterwards and reinserts the jump itself.
- An `ExecStartPost` restarts fail2ban when it is already running, which covers a manual restart of
  the unit. It is guarded by `is-active` so it is a no-op at boot, and uses `--no-block`, because
  waiting on a unit ordered after this one would deadlock.

Verify the jump is first, not merely present. Read it a few seconds after any fail2ban restart, since
`systemctl restart` returns before fail2ban has inserted the rule and a chain read in that window is
misleading.

### IPv6 is unreachable from outside for an unrelated reason

The host holds `2a02:c206:3015:7801::1/64` with a default route, and no AAAA record is published for
`sdwa5.org`. An inbound SSH attempt straight to the address returns `No route to host` from a client
with working IPv6, and the `ip6tables` `INPUT` policy counter reads **0 packets, 0 bytes**, so nothing
arrives at the host at all. The block is therefore upstream of it, and predates this change.

The IPv6 rules are in place regardless, so that publishing an AAAA record later does not silently
expose an unfiltered stack.

### Result

```
22    OPEN
80    OPEN
443   OPEN
25, 2019, 5355, 8000, 8001, 8002, 8443, 3306   filtered
```

Web, HTTP/3 on UDP 443, SSH and ICMP all verified working afterwards from outside.

### Installation

```bash
cd /opt/docker && git pull --ff-only
install -m 755 -o root -g root hardening/firewall/sdwa5-firewall.sh /usr/local/sbin/sdwa5-firewall.sh
install -m 644 -o root -g root hardening/firewall/sdwa5-firewall.service /etc/systemd/system/
install -m 644 -o root -g root hardening/systemd/resolved.conf.d/10-no-llmnr.conf /etc/systemd/resolved.conf.d/
systemctl daemon-reload
systemctl enable --now sdwa5-firewall.service
systemctl restart systemd-resolved
```

**Arm an auto-revert before the first apply**, because a mistake here costs the SSH session. A
snapshot plus a timer means the box repairs itself in fifteen minutes instead of needing the console:

```bash
D=/root/fw-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$D"
iptables-save > "$D/rules.v4"
printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$D/rules.v6"
printf '#!/bin/bash\niptables-restore < %s/rules.v4\nip6tables-restore < %s/rules.v6\nsystemctl restart fail2ban\n' "$D" "$D" > /root/fw-revert.sh
chmod +x /root/fw-revert.sh
systemd-run --on-active=15min --unit=fw-revert /root/fw-revert.sh
# ... apply, then prove a NEW ssh session works, then:
systemctl stop fw-revert.timer
```

Note that `ip6tables-save` writes an **empty file** on this host, exiting 0. The nft backend has no
`ip6` filter table until something creates one, while `ip6tables -S` synthesises the default policies
and so looks normal. An empty restore file is a silent no-op, which is why the IPv6 baseline above is
written by hand. Validate both with `iptables-restore --test` before trusting them.

## The `admin` account, and why uid 1000 is not free

Settled 2026-09-08. It gets **neither an SSH key nor deletion**, and the reason is a uid collision
that is easy to miss.

**The Dolibarr image defines its own `www-data` as uid 1000.** On the host that maps to `admin`, and
3461 files totalling 64 MB under `dolibarr-documents-data` and `dolibarr-custom-data` are owned by
it. Deleting the account frees uid 1000, `adduser` hands out the lowest free uid, and the next
account created on this host would silently inherit ownership of every Dolibarr document. The account
therefore stays, purely to reserve the uid. Its GECOS field says so, because `getent passwd` is where
someone will look.

**It does not need a key.** Last interactive login was 18 June 2025. Administration is root over SSH
with a key, and break-glass is the Contabo console as root, whose password Contabo can reset from the
panel.

**The collision is also the risk.** Host uid 1000 is a public-facing container's web server uid, and
that uid was in the host's `sudo` group. Anything that achieved host execution as uid 1000 would have
inherited that. What changed:

| | Before | After |
|---|---|---|
| groups | `admin sudo www-data users` | `admin users` |
| shell | `/bin/bash` | `/usr/sbin/nologin` |
| password | usable | locked |
| `authorized_keys` | none | none |

Locking the password and changing the shell does not touch the containers. They resolve uid 1000
through their own `/etc/passwd`, never the host's. Verified afterwards: 10 uid 1000 processes still
running, all 3461 files still owned, Dolibarr still returning 200, all three containers healthy.

## Break-glass

**The Contabo console is the fallback and nothing in this document affects it.** It logs in through
getty and PAM rather than sshd, so `PasswordAuthentication no` does not touch it. If the key is ever
lost:

1. Contabo panel, reset the root password if needed, open the VNC console.
2. Log in as root. `admin` cannot be used since 2026-09-08, see the section on it below. Contabo
   can reset the root password from the panel, so this route never depends on a stored credential.
3. Append a fresh public key to `/root/.ssh/authorized_keys`.

That is why disabling SSH password authentication costs nothing in recoverability. SSH passwords
were never the fallback.

## Installation

```bash
cd /opt/docker
git pull --ff-only
apt install -y fail2ban

install -m 644 -o root -g root hardening/sshd_config.d/10-hardening.conf /etc/ssh/sshd_config.d/10-hardening.conf
install -m 644 -o root -g root hardening/fail2ban/jail.local             /etc/fail2ban/jail.local

sshd -t && systemctl reload ssh          # validate BEFORE touching the running service
systemctl restart fail2ban
```

Use `reload`, not `restart`, so existing sessions survive. Keep the working session open and prove a
second one before closing it.

## Verification

```bash
# effective config, which is the only trustworthy source
sshd -T | grep -iE '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|maxstartups)'

# key login works
ssh -o ControlPath=none sdwa5.org true && echo ok

# password auth is refused. The error must read "(publickey)" and not "(publickey,password)"
ssh -F /dev/null -o BatchMode=yes -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive root@sdwa5.org true
ssh -F /dev/null -o BatchMode=yes -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive admin@sdwa5.org true

# fail2ban
fail2ban-client status sshd

# no Failed password lines should appear at all
journalctl -u ssh --since '-5 min' | grep -c 'Failed password'
```

### Two testing traps worth knowing

**A reload does not change connections already in flight.** `Received SIGHUP; restarting` re-execs
the listener, but already-forked children keep the old config until they exit, and `LoginGraceTime`
is 120 seconds. `Failed password` lines therefore keep appearing for up to two minutes after the
reload, from processes with PIDs lower than the new listener's. Measure a window that starts after
the reload, not one that straddles it.

**`ssh -i` appends to the identity list, it does not replace what the config supplies.** Testing
whether the old key is still accepted with `ssh -i ~/.ssh/id_rsa sdwa5.org` offers both that key and
the one from `conf.d`, the good one succeeds, and the test reports a false pass. Use `-F /dev/null`.
Also pass `-o ControlPath=none`, or connection multiplexing reuses an authenticated master and the
test never authenticates at all.

## Open items

- Second copy of `id_ed25519_sdwa5` on the notebook. The key went into Vaultwarden on 2026-09-08, so
  the workstation is no longer the only holder, but a rescue console cannot fetch a vault item and
  every client is logged out for a while after a KDF change. The Contabo console stays the break-glass
  behind both.
- IPv6 is unreachable from outside, and the cause is upstream of this host rather than in its
  configuration. Worth resolving before any AAAA record is published. See the firewall section.
