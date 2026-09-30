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

### The outbound key, which is how this host reaches GitHub

Everything above is about getting **in**. This host also authenticates **out**, because `/opt/docker`
is a git checkout that pulls this repository, and until 2026-09-08 it did so with the wrong kind of
key.

| Key | Purpose | Registered as | Passphrase |
|---|---|---|---|
| `/root/.ssh/id_ed25519_sdwa5vps_20260915` | pull `SdWa5/vps` into `/opt/docker` | deploy key on `SdWa5/vps`, id 163344886, `read_only: true` | no |
| `/root/.ssh/id_ed25519_chimodiazz_20260915` | pull `chimodiazz/website` into `/opt/docker/chimodiazz-src` | deploy key on `chimodiazz/website`, `read_only: true` | no |

Fingerprint `SHA256:cSSIrs739ebFZEOrHkSYQJwCmlgjVnRaApdhJieYHhw`. The private half was generated on
this host and has never crossed the network. It is the **third** key in this role, and the reason is
below.

**What it replaced, and why that mattered.** The old `/root/.ssh/id_ed25519` was registered as an
*account-level* key on the `bestcodename` user, titled "sdwa5.org Contabo VPS". An account key carries
the account's whole reach, so root on this VPS had read **and write** access to every repository that
account can see, while the machine needs to pull exactly one. A compromise of this host was therefore
a compromise of every repository. The key was deleted, GitHub id 155997825.

`/root/.ssh/config` pins the new key so nothing else can be offered by accident:

```
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_sdwa5vps_20260915
    IdentitiesOnly yes
```

`IdentitiesOnly yes` is the load-bearing line. Without it ssh offers every key it can find. Measured on
2026-09-30, `/root/.ssh/` holds only the two keys in the table above, so no superseded key is left to
offer, and the line stays so that a key added later cannot be offered by accident either.

**A second outbound key was added on 2026-09-15**, for `chimodiazz/website`. GitHub refuses the same
deploy key on two repositories, so a shared key was never an option, and an account key is the thing
this section exists to argue against. It gets its own alias rather than a second `IdentityFile` under
`Host github.com`, because `IdentitiesOnly yes` offers the listed keys in order and GitHub answers as
whichever repository the first accepted key belongs to:

```
Host github-chimodiazz
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_chimodiazz_20260915
    IdentitiesOnly yes
```

Verified 2026-09-15, both greetings in one session: `ssh -T github-chimodiazz` answers
`Hi chimodiazz/website!` and `ssh -T github.com` still answers `Hi SdWa5/vps!`. **The `git_remote`
health check does not cover the new key**, so its death would be as silent as the old one's was. See
[chimodiazz.md](chimodiazz.md).

**The greeting is the clearest proof of scope**, because a deploy key identifies as the repository
rather than as the account:

```sh
ssh -T git@github.com            # Hi SdWa5/vps! not Hi bestcodename!
cd /opt/docker && git ls-remote origin HEAD    # succeeds
cd /opt/docker && git push --dry-run origin main   # refused, no write access
```

Verified in that order on 2026-09-08 and again on 2026-09-15, and a superseded key is deleted only
after the pull has been proven to work through its replacement. **The greeting is also the fastest way
to catch the failure above**, because a dead deploy key still authenticates and names the repository
it died with.

**Pushing from this host now fails, by design.** Nothing in this repository does. The deploy
automation in [TODO.md](../TODO.md) runs the other way round, a GitHub Action reaching *in* to the
host, so it is unaffected and will need its own key held as a GitHub secret.

**The deploy key has no passphrase, and that is not a gap that could be closed.** An unattended puller
cannot answer a prompt. The two ways round that are an `ssh-agent` unlocked at boot and a passphrase
kept in a file, and both put the thing that unlocks the key on the same disk as the key, for the same
reader. A passphrase defends a key that travels; this one never leaves the host. So the mitigation is
the key's **scope**, which is one repository and read-only, plus mode `600` and the fact that reading
it at all already requires root. That is strictly better than what it replaced, which also had no
passphrase and carried the whole account.

**A DEPLOY KEY BELONGS TO THE REPOSITORY OBJECT, AND RECREATING THE REPOSITORY DESTROYS IT.** This is
the operational fact behind the third key. The redaction passes of 2026-09-12, 2026-09-13 and
2026-09-15 each republished by renaming the repository, creating an empty one under the old name and
deleting the rename, because that is what clears GitHub's cache of pre-rewrite objects. The deploy key
travels with the **renamed** repository and dies with it, so after each pass `/opt/docker` could no
longer pull, while `ssh -T` still authenticated and cheerfully greeted the deleted name.

**And the same public key cannot simply be re-registered.** GitHub answers
`key is already in use` (HTTP 422) for a key whose repository is gone, although it then appears on no
repository and on no account. Measured again on 2026-09-15. So each pass needs a **freshly generated
keypair**, not a re-registration.

**Nothing on this host notices.** The nine health checks cover disk, containers, backups, HTTP, Caddy,
the firewall and the Vaultwarden version, and not one of them asks whether the checkout can still
reach its remote. That is filed in [TODO.md](../TODO.md).

The two superseded keys were deleted on 2026-09-15, after checking that neither fingerprint appeared
on the account or on any repository, that neither was in an `authorized_keys`, that no cron job or
script on this host invokes `ssh`, and that `known_hosts` has only ever held `github.com`.

Client-side detail, including the `~/.ssh/conf.d` layout and where each of the five keys is backed up,
is documented in `~/PhpstormProjects/ai/docs/ssh-keys.md`, and the replacement procedure with its
ordering is under "The deploy key replacement, and the order that makes it safe".

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

**Every *running* Docker publish binds `127.0.0.1`**, which is why nothing was exposed through Docker
on the day. That is a statement about what was running, not about the compose file, and the two are
different:

```
docker-compose.yml:47    minecraft   "25565:25565"   all interfaces, profile-gated, public on purpose
docker-compose.yml:179   ollama      "11434:11434"   all interfaces, profile-gated, no auth
```

Both profiles were down, so neither port was open, and both become public the moment their profile
starts.

### Published container ports are filtered in DOCKER-USER, not in INPUT

Stated plainly because the opposite is the intuitive reading of a `DROP` policy on `INPUT`, and
because until 2026-09-08 this firewall genuinely did not cover them.

A published port is DNAT'd in `nat/PREROUTING` and the packet then traverses **`FORWARD`**, never
`INPUT`. Measured on the host:

```
nat PREROUTING : -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
FORWARD        : -A FORWARD -j DOCKER-USER
                 -A FORWARD -j DOCKER-ISOLATION-STAGE-1
DOCKER-USER    : -A DOCKER-USER -j RETURN          <- Docker's empty default
```

`DOCKER-USER` is the hook Docker provides for the operator. It creates the chain empty, jumps to it
from the head of `FORWARD` and never puts rules in it, so taking it is the intended use rather than a
trespass on Docker's own chains. `sdwa5-firewall.sh` now owns it alongside `INPUT`.

What it holds, in order:

| Rule | Why |
|---|---|
| `ESTABLISHED,RELATED` → `RETURN` | without it every reply a container waits for is dropped |
| each Docker bridge → `RETURN` | container egress and traffic between containers |
| `eth0` tcp and udp 25565 → `RETURN` | `minecraft` publishes on all interfaces on purpose |
| `eth0` anything else → `DROP` | what an accidental `0.0.0.0` publish runs into |
| `RETURN` | hand the rest back to Docker |

**Every allow is a `RETURN` and never an `ACCEPT`.** `RETURN` hands the packet back to `FORWARD` so
Docker's `DOCKER-ISOLATION` and `DOCKER` chains still judge it. `ACCEPT` would skip them and quietly
switch off Docker's network isolation between compose projects, which is a bigger hole than the one
being closed.

What the firewall now buys:

| | Covered |
|---|---|
| A host daemon binding `0.0.0.0`, as LLMNR did | yes, in `INPUT` |
| A container published on `0.0.0.0` over IPv4 | yes, in `DOCKER-USER` |
| A container published over IPv6 | not applicable, see below |

**There is no IPv6 half, and that is measured rather than skipped.** Docker does no IPv6 publishing
on this host, measured 2026-09-08: `ip6tables` holds zero Docker rules, the v6 `nat` table holds zero
DNAT entries, both bridges carry only a link-local `fe80::` address, and there is no
`/etc/docker/daemon.json` at all, so Docker runs with IPv6 off by default. There is therefore no v6
path to a container to filter, and writing v6 rules would be defending an empty path. Enabling
Docker's IPv6 changes that, and a v6 counterpart then has to be written with `nft`, because
`ip6tables` reports the v6 `DOCKER-USER` chain as `incompatible, use 'nft' tool`.

**The `firewall` check in [monitoring.md](monitoring.md) watches this**, and CRITs when `DOCKER-USER`
is missing or has fallen back to a bare `-j RETURN`. Anything that flushes the chain, including a
Docker restart, would otherwise leave every published port unfiltered while the chain still looks
present.

### fail2ban's jump is re-added by the script, because fail2ban does not

This replaced an arrangement that did not work, and it was caught by the new `DOCKER-USER` check
firing on its own first deployment.

Flushing `INPUT` removes the jump fail2ban puts at its head. The unit used to carry an
`ExecStartPost` that restarted fail2ban so fail2ban would re-insert it, and the previous version of
this document asserted that it did. **Measured 2026-09-08, it does not.** After
`systemctl restart sdwa5-firewall`, fail2ban restarted and logged `Server ready` and
`Creating new jail 'sshd'`, and thirty seconds later the jump was still absent. The same three
commands run by hand insert it without complaint, so the cause inside fail2ban 1.0.2 is **not
established, only the effect is**. The effect is what matters: every firewall restart and every boot
silently switched off SSH brute-force filtering while `iptables -S INPUT` still looked plausible.

So `sdwa5-firewall.sh` re-adds the jump itself, deterministically, and only when the `f2b-sshd` chain
exists, because creating that chain is fail2ban's job and a jump to a missing chain fails.

**Dropping the fail2ban restart buys a second thing.** A fail2ban restart logs
`Flush ticket(s) with iptables-multiport` and discards every active ban, so the old arrangement threw
away the bans it was trying to protect. Bans now survive a firewall restart, because nothing here
touches the `f2b-sshd` chain.

One thing to avoid, learned the hard way while diagnosing this. **`fail2ban-client stop <jail>` is
not reversible with `start <jail>`.** `stop` removes the jail from the running server and `start` then
fails with `UnknownJailException`, leaving the jail not running at all. Use
`systemctl restart fail2ban` instead.

Credit where due. The gap was caught by a parallel session reading this file, after the document had
already asserted the opposite in the sentence above it.

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

### IPv6, and two wrong conclusions before the right one

The host holds `2a02:c206:3015:7801::1/64` with a default route via `fe80::1`, and **no AAAA record is
published** for `sdwa5.org` or `vault.sdwa5.org`, so nothing uses IPv6 for the services today.

**Both directions work.** Measured 2026-09-08 from a Mullvad exit in Sweden with IPv6 enabled in the
tunnel:

```
outbound   6/6 to 2001:4860:4860::8888 and 2606:4700:4700::1111
inbound    ping 3/3, 0% loss, 58 ms
inbound    ssh -6 root@2a02:c206:3015:7801::1 logs in
```

`curl -6 https://[2a02:...]/` returns `000` and that is **not** a network failure. A literal-IP URL
sends no SNI and Caddy closes the handshake, which is correct behaviour.

**One transient failure was seen and never reproduced.** An identical test earlier the same day failed
completely, from a different Mullvad relay, with `Destination unreachable: Address unreachable`
returned by `2a02:c205::1eaf`, which is verified as Contabo GmbH on AS51167.

The obvious mechanism was neighbour cache expiry, since nothing here normally emits IPv6 and Contabo's
router would have no reason to hold an entry for the VM. **That hypothesis was tested and is refuted.**
IPv6 was left idle for 25 minutes, in a window chosen to exclude the hourly health-check cron at
`:17`, and inbound was then probed cold with every control connection forced to IPv4 so it could not
refresh anything:

```
after 25 min idle, before any outbound packet from the VM:
  ping    0% packet loss
  ssh -6  reachable
after making the VM transmit once:
  ping    0% packet loss
  ssh -6  reachable
```

Cold and warm behave identically, so the single failure was transient and its cause is unknown. Do not
open a provider ticket on it. If it recurs, capture the relay or path in use at the time, because that
is the variable this experiment could not control.

Reading the counters is what makes this trustworthy. A cold inbound ping increments the ICMPv6 rule by
exactly **one**, not by the number of echo requests, because conntrack treats the exchange as one flow
and the rest land on `ESTABLISHED,RELATED`. An SSH login likewise adds one packet to `tcp dpt:22`. A
counter that moves by less than the packets sent is normal here and is not evidence of loss.

### What this cost, and the rule that comes out of it

Three conclusions were drawn here and the first two were wrong.

**First**, inbound was reported as blocked upstream. The evidence was a zero `ip6tables` counter and
`No route to host`, while the test client's Mullvad tunnel had `IPv6: off` and was blocking IPv6
outright, so those ICMPv6 errors came from the client's own address.

**Second**, after fixing the client, inbound was reported as broken at Contabo's last hop and a
support ticket was recommended. That rested on one failed window treated as a steady state.

**Third**, and only after being challenged, a repeat test showed inbound working.

Two rules follow. **A negative network result needs repetition before it becomes a conclusion**, since
a single failed window and a permanent fault look identical. And **check every counter, not the
convenient ones**. The check that missed this filtered the `ip6tables` output to the policy and the
TCP rules, so an inbound ICMPv6 packet would have been accepted, counted on the line that was filtered
out, and never seen.

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
- **There is no account allowlist.** Measured 2026-09-17: sshd has no `AllowUsers`, no
  `AllowGroups` and no `DenyUsers`, and not a single `Match` block, so any account on this host
  that carries a key can log in. That was harmless while `root` was the only such account and
  `admin` had no key. It stops being harmless the moment a second account is created, which is
  what TODO item 10.1 proposes, so the `AllowGroups` belongs in the same change.
- Inbound IPv6 is unverified. Outbound works, no AAAA record is published, and the client used for
  testing had IPv6 blocked by its VPN. Settle it from a host with working IPv6 before publishing an
  AAAA record. See the firewall section.
