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

The private key is stored in Vaultwarden, which is the private vault, and a second copy belongs on
the notebook.

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

## Break-glass

**The Contabo console is the fallback and nothing in this document affects it.** It logs in through
getty and PAM rather than sshd, so `PasswordAuthentication no` does not touch it. If the key is ever
lost:

1. Contabo panel, reset the root password if needed, open the VNC console.
2. Log in as root or `admin`.
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

- Second copy of `id_ed25519_sdwa5` on the notebook, and the key into Vaultwarden. Until then the
  workstation is the only holder, with the Contabo console behind it.
- `admin` can no longer log in over SSH, because it has no `authorized_keys`. That is intended.
  If it should be reachable, give it a key rather than re-enabling passwords.
- No firewall. `iptables -P INPUT ACCEPT` with no rules, so every port a service opens is public.
  fail2ban manages its own chain and does not change that. Tracked in [TODO.md](../TODO.md).
