# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- `TODO.md` item 7.3 now tracks finishing the emergency access enrolment with the new member, in progress
  since 2026-09-08, rather than asking which remedy to pick. It names the verification,
  `SELECT COUNT(*) FROM emergency_access;`, which is still zero.

### Removed

- `TODO.md` item on the two dormant Vaultwarden accounts. Decided 2026-09-08 to keep both, recorded
  in the parent repo's `docs/services.md`.

## [1.14.0] - 2026-09-08

### Fixed

- **The IPv6 finding in 1.11.0 was wrong and is corrected.** `docs/ssh-hardening.md` claimed inbound
  IPv6 was blocked upstream of this host. Inbound is unverified, not broken. The evidence was an
  `ip6tables` policy counter of zero packets plus `No route to host` from the workstation, and the
  actual cause was the workstation's Mullvad tunnel, which has `IPv6: off` and blocks IPv6 while
  connected. Those ICMPv6 errors were generated locally by the test client's own address. Outbound
  IPv6 from the host works, measured at 0% loss and 7 ms.
- `docs/monitoring.md` no longer rests the firewall check's IPv6 WARN on that claim. It rests on the
  absence of an AAAA record, which is measured, and says to raise it to CRIT if one is published.

### Changed

- `TODO.md` items 7.2 to 7.4 rewritten from measurement rather than assumption. Of the three accounts
  on PBKDF2, only one holds anything, with a number of items. The other two hold zero. The single-owner item
  now names what is at stake, a small number of ciphers, and what the two remedies cost.

### Added

- `TODO.md` item for the two dormant Vaultwarden accounts, and one for settling inbound IPv6.
- `docs/ssh-hardening.md` records the two traps behind the wrong finding. A zero counter on a DROP
  policy is ambiguous between "nothing arrived" and "nothing was sent", and a client must be proven
  capable before anything is concluded about the server.

## [1.13.0] - 2026-09-08

### Changed

- The `admin` account gets neither an SSH key nor deletion. It is removed from the `sudo` and
  `www-data` groups, its password is locked and its shell is `/usr/sbin/nologin`. It keeps no
  `authorized_keys`.
- Its GECOS field now records why it must not be deleted, because `getent passwd` is where someone
  will look before running `userdel`.
- The break-glass procedure names root only. `admin` can no longer log in at the console either, and
  Contabo can reset the root password from the panel, so that route depends on no stored credential.

### Removed

- `TODO.md` item on deciding the fate of the `admin` account.

### Notes

- The decision turns on a uid collision. The Dolibarr image defines its own `www-data` as uid 1000,
  which maps to `admin` on the host, and 3461 files totalling 64 MB under `dolibarr-documents-data`
  and `dolibarr-custom-data` are owned by it. Deleting the account frees uid 1000, `adduser` hands out
  the lowest free uid, and the next account created would silently inherit ownership of every Dolibarr
  document. The account stays to reserve the uid.
- The same collision was the risk. Host uid 1000 is a public-facing container's web server uid and it
  sat in the host's `sudo` group, so anything achieving host execution as that uid would have
  inherited sudo membership.
- Containers resolve uid 1000 through their own `/etc/passwd` and never the host's, so locking the
  password and changing the shell does not affect them. Verified afterwards with 10 uid 1000 processes
  still running, all 3461 files still owned, Dolibarr returning 200 and all three containers healthy.

## [1.12.0] - 2026-09-08

### Added

- `monitoring/vps-health.sh` gains `check_firewall`. It alerts when the IPv4 `INPUT` policy is not
  `DROP`, when fail2ban's `f2b-sshd` jump is missing, and when a port in `FIREWALL_PORTS` is no longer
  accepted. Without it the firewall added in 1.11.0 could disappear unnoticed, because anything that
  flushes `INPUT` leaves a chain that still looks plausible.
- `FIREWALL_PORTS` tunable, default `22 80 443`.
- Six tests in `tests/vps-health.bats` covering an ACCEPT policy, a missing fail2ban jump, a dropped
  service port, an unreadable chain, an open IPv6 policy and several faults at once. `tests/stubs/iptables`
  and `tests/stubs/ip6tables` are new, and `common_setup` now installs a healthy chain by default.
- `docs/monitoring.md` documents the check and why IPv6 is a WARN rather than a CRIT.

### Changed

- A missing `iptables` binary or an unreadable `INPUT` chain is CRIT rather than silently passing. A
  check that cannot see its subject has confirmed nothing, and silence would read as healthy.
- All firewall faults are reported in one line rather than one per run, so a single mail carries the
  whole picture instead of the first problem only.

## [1.11.0] - 2026-09-08

### Added

- `hardening/firewall/sdwa5-firewall.sh` and `sdwa5-firewall.service`. Default-deny `INPUT` for IPv4
  and IPv6, allowing loopback, established and related, ICMP, the Docker bridges and 22, 80 and 443.
  Enabled at boot.
- `hardening/systemd/resolved.conf.d/10-no-llmnr.conf`. Turns LLMNR and mDNS off, which closed 5355
  on TCP and UDP for both families. It was the only unnecessary port open to the internet.
- `docs/ssh-hardening.md` gains a firewall section covering the measured exposure before the change,
  why `iptables-restore` and `iptables-persistent` are not used, the fail2ban flush problem and the
  IPv6 finding.
- `hardening/firewall/sdwa5-firewall.sh` added to the shellcheck list in `tests/run.sh`, which is an
  explicit file list rather than a glob and would otherwise never have covered it.

### Changed

- The firewall is defence in depth rather than a repair. Measured before the change, every Docker
  publish already bound `127.0.0.1`, along with exim4 and the Caddy admin API, so only 22, 80, 443
  and 5355 were public. The value is protection against the next service that binds `0.0.0.0` by
  accident.
- The script rewrites `INPUT` alone instead of restoring a saved table. Docker owns `DOCKER`,
  `DOCKER-USER`, `DOCKER-ISOLATION-*` and a set of `FORWARD` rules and rebuilds them at its own start,
  so a restored snapshot would replay stale copies referring to bridges that may no longer exist. This
  also makes the script idempotent.
- The unit is ordered `Before=fail2ban.service` and restarts fail2ban from `ExecStartPost` when it is
  already running. Flushing `INPUT` removes fail2ban's jump, which would leave SSH unfiltered while
  still looking correct. The `ExecStartPost` is guarded by `is-active` so it is a no-op at boot, and
  uses `--no-block`, because waiting on a unit ordered after this one would deadlock.

### Notes

- IPv6 is unreachable from outside for a reason upstream of this host. It holds
  `2a02:c206:3015:7801::1/64` with a default route and no AAAA record is published. Inbound SSH to the
  address returns `No route to host` from a client with working IPv6, and the `ip6tables` `INPUT`
  policy counter reads 0 packets, so nothing arrives at all. The v6 rules are in place regardless, so
  that publishing an AAAA record later does not expose an unfiltered stack.
- `ip6tables-save` writes an empty file on this host and exits 0, because the nft backend has no `ip6`
  filter table until something creates one, while `ip6tables -S` synthesises the default policies and
  looks normal. An empty restore file is a silent no-op, so an auto-revert built from it protects
  nothing.

### Changed

- `docs/ssh-hardening.md` — `id_ed25519_sdwa5` is in Vaultwarden since 2026-09-08, as item
  `00fceed1-965b-4857-9b91-2d371d0c6662`. It was uploaded by path so the key never passed through a
  command line or the process list, then downloaded again and compared byte-for-byte against the file
  on disk. The open item narrows to the notebook copy alone, which stays open because a rescue console
  cannot fetch a vault item and every client is logged out for a while after a KDF change.

### Added

- `docs/shopware/TODO.md` item 5.4, actual preorders. Binding prepaid orders for merch not yet in
  stock, motivated by financing rather than by the feature itself, since bulk pricing needs capital
  the association does not have before it has sold anything. Distinguishes it from 5.3, which only
  measures interest. Names the three open decisions: when the money is taken, the minimum quantity and
  the refund path if the run does not happen, and the legal wording for a binding prepaid sale, which
  belongs in the same AGB pass as item 13.

## [1.10.0] - 2026-09-07

### Changed

- Back on `vaultwarden/server:latest`. The testing pin from 1.8.0 existed only to get the master
  password changed, that is done, and a tagged release is the right default for a password vault.
  The weekly auto-update tracks releases again, so 1.37.3 will arrive on its own rather than needing
  a version-drift warning as a cue.
- `monitoring/vaultwarden-autoupdate.sh` back to `IMAGE=vaultwarden/server:latest`, matching compose.
  `docs/infrastructure.md` and `docs/monitoring.md` follow.
- `docs/vaultwarden.md` — the testing section is now a record of why it was needed and how to do it
  again, rather than a description of current state. It gains the reason the revert was cheap: the
  testing build applied **no** schema migration, the newest row in `__diesel_schema_migrations` being
  `20260505120000` from 2026-09-01, so the schema matched what 1.37.2 expects and no snapshot restore
  was involved. A build that had applied one would have made the revert a restore instead, losing the
  master password and KDF changes with it, so the check is documented as a precondition.

### Added

- `docs/vaultwarden.md` lists what stays broken on the release, so it is not rediscovered. Master
  password change and reset two-step login are both broken by the same payload change, #7659 and
  #7674. Organisation import into a collection is broken by #7698, confirmed with `.kdbx` through the
  SDK importer where the payload omits `groups` and `users` that Vaultwarden requires but never reads.
  Personal import from a password-protected `.json` export is unaffected, because such an export
  carries neither field, and that is the disaster-recovery path that matters.

### Removed

- `TODO.md` item 7.6, returning to a tagged release, which this release does.

## [1.9.0] - 2026-09-07

### Added

- `docs/vaultwarden.md` — runbook for a mobile client that cannot log in after a password or KDF
  change. The tell is the `devices` table rather than the log: the Android app's `updated_at` predated
  the change by over an hour, a log capture over the attempt window was empty, and no authentication
  had been rejected anywhere, so the failure was entirely local. A locked Bitwarden client holds a
  stale `kdfConfig` and a user key wrapped with the old master key, and never calls the server, so it
  cannot learn that anything changed. Clearing the app's storage and logging in fresh fixed it.
  Records that a second factor and a pending new-device verification were both ruled out, since both
  produce the same symptom.
- `docs/vaultwarden.md` — the rotation performed on 2026-09-07 is recorded in the "Master password and
  KDF" section, together with the fact that `private_key` and `public_key` were unchanged, which is
  the proof that "Rotate account encryption key" was left off.
- `docs/vaultwarden.md` step 7 now warns that the mobile app is expected to refuse the new password at
  its lock screen, so the reader does not read it as a fault and retry.
- `TODO.md` items 7.6 and 7.7: returning to a tagged release once one above 1.37.2 exists, and the
  fact that emergency access is enabled but nobody is enrolled while the SdWa5 org has a single owner,
  which leaves a forgotten master password unrecoverable for all four accounts.

### Changed

- The account now uses Argon2id at 64 MiB, 3 iterations, parallelism 4, verified from the database.
  451 ciphers intact. The other three accounts remain on PBKDF2 600,000, which only their holders can
  change.

## [1.8.0] - 2026-09-07

### Changed

- Vaultwarden runs `vaultwarden/server:testing`, pinned by digest
  `sha256:4d840a0d45e51389297bb69dead79e8a549afa2d7a9d3db3221123a02668e441`, reporting
  `1.37.2-a6c3bd6d`. Changing the master password is broken in the 1.37.2 release: the bundled web
  vault sends Bitwarden's newer payload with `authenticationData` and `unlockData`, while the handler
  still expects `newMasterPasswordHash`, so the request fails with 422 before reaching the database
  and the client shows only "An error has occurred". Upstream issue #7659, duplicate of #7622, fixed
  by PR #7634 around 2026-08-29 and not in any tagged release. Downgrading to 1.37.0 also fixes it and
  was rejected, because it breaks the browser extensions, which is the September 2026 incident already
  recorded in `docs/vaultwarden.md`.
- The pin is a digest rather than the floating `testing` tag on purpose. `testing` tracks main, and a
  floating tag would let the weekly auto-update move this vault onto whatever main-branch happens to
  be, every Sunday, unattended. With a digest, `docker-compose pull` is a no-op.
- `monitoring/vaultwarden-autoupdate.sh` follows the same pin, so it compares the right image rather
  than still inspecting `vaultwarden/server:latest` while compose points elsewhere. Its help text and
  failure mail no longer hardcode the tag.
- `docs/vaultwarden.md` gained a "Temporarily on the testing image" section covering the reason, why
  the digest pin, and the route back. `docs/infrastructure.md` and `docs/monitoring.md` follow.

### Added

- The route back is documented and self-signalling. `monitoring/vps-health.sh` strips the `-a6c3bd6d`
  suffix, so it reads `1.37.2` and stays quiet today. The moment a release above 1.37.2 appears it
  warns that the server is behind, and that warning is the cue to return to `latest`.

### Changed

- `docs/ssh-hardening.md` records that this host is not exposed by the unprotected copies of the old
  keys still on stefan-notebook, because `id_rsa` was removed from its `authorized_keys` and
  `id_ed25519_sdwa5` does not exist on that machine. Replacing the key rather than only adding a
  passphrase to it is what bought that.

- `docs/ssh-hardening.md` and `TODO.md` item 7.2 corrected. `id_ed25519_sdwa5` does belong in
  Vaultwarden, which is the private vault for a private key. The original reasoning, that Vaultwarden
  running on the host the key unlocks makes storing it there circular, only applies when the server
  and every logged-in client are unavailable at once, because Bitwarden clients cache the vault and
  unlock offline. What survives is that a KDF or master password change logs out every client for a
  while, and that a vault item cannot be fetched from a rescue console, so the notebook copy stays on
  the list and the Contabo console remains the break-glass.

## [1.7.0] - 2026-09-07

### Added

- `hardening/sshd_config.d/10-hardening.conf` and `hardening/fail2ban/jail.local`, the deployable host
  SSH configuration, byte-identical to what runs on the VPS. Applied after finding 13,672 failed root
  logins in the previous 24 hours, escalating to several hundred attempts per minute during the work,
  against a host with `PasswordAuthentication yes`, `PermitRootLogin yes`, no firewall and no
  fail2ban. `PasswordAuthentication no`, `PermitRootLogin prohibit-password` and `MaxStartups
  30:50:200` now apply, and `Failed password` went from roughly 180 per minute to zero.
- `docs/ssh-hardening.md`, recording the finding, the change, the verification and the break-glass
  path. Includes the two traps that produce false results when testing this: a reload leaves
  already-forked sshd children on the old config for up to `LoginGraceTime`, and `ssh -i` appends to
  the identity list rather than replacing what the config supplies, so a "key still works" test can
  pass on the wrong key.
- fail2ban with the sshd jail. The Debian default fails to start on this host with "Have not found
  any log file for sshd jail", because sshd logs to journald only and there is no rsyslog or
  `/var/log/auth.log`, so `backend = systemd` is set explicitly. 71 addresses banned in the first
  hour.
- `README.md` gained a "Host access" section and both new documents in the index.
- `docs/infrastructure.md` gained the sshd node and edge in the diagram, the `hardening/` and
  `vaultwarden-db-backup/` directories in the layout, and the daily database copy in the cron table,
  which had been missing since 1.6.0.
- `TODO.md` item 7, the security follow-ups: no firewall at all, the notebook key copy, what to do
  about the `admin` account, the parent repo's `docs/services.md` claiming one Vaultwarden user where
  the database holds four, and the other three accounts still being on PBKDF2.

### Changed

- root's `authorized_keys` on the VPS holds one personal ed25519 key,
  `SHA256:3r0Dk1tFl8W/iHyFC6rsOFbQ1JznqEeP5+06iYug0mA`, instead of the 8196-bit work RSA key
  `sri@sri-VirtualBox` that was previously its only entry. That work key is also used for
  `github.com` and `git.myndc.de`, and a work credential holding sole root on the private box that
  carries the vault is a boundary problem in both directions. The old key is verified rejected.

### Fixed

- `/etc/ssh/sshd_config.d/50-cloud-init.conf` contained `PasswordAuthentication yes` and silently
  overrode the `PasswordAuthentication no` already present at line 57 of `sshd_config`, because the
  `Include` sits at line 12 and sshd uses the first occurrence of a keyword. Editing the main file
  changed nothing. `10-hardening.conf` sorts before the cloud-init file and therefore wins, which
  also survives `cloud-init.service` rewriting its own file on every boot.

### Added

- `docs/vaultwarden.md` — new step 3 in the master password order of operations: memorise the password before changing
  anything, gated on two cold successes on separate days with at least one after a night's sleep rather than on a
  repetition count. Records that the copy stays on paper while learning, because a Bitwarden item would sit in a vault
  still protected by the old password and a master password change re-wraps the user key rather than re-encrypting each
  item, and that neither is a backup. Later steps renumbered to 4 through 8. Amended the same day to
  keep no copy at all rather than a paper one, using `genpass.py --show --verifier` and `--check` from
  the workstation docs, since a password not yet in use costs nothing to lose and only recall needs
  verifying.
- `docs/vaultwarden.md` points at `~/PhpstormProjects/ai/docs/password-strength.md` for the master password length
  analysis, and names the outcome of 18 lowercase characters with at least one digit so the answer is available
  without leaving this repository.

### Fixed

- `monitoring/vps-health.sh` padded the check-name column to 20 characters in the `--dry-run` output
  and in the alert mail body. `vaultwarden_db_backup` is 21, so it pushed the status column out of
  line on that row. Widened to 21.
- `.gitignore` did not cover the `vaultwarden-data.bak-*` snapshots that
  `monitoring/vaultwarden-autoupdate.sh` writes, so the deploy checkout at `/opt/docker` always
  reported a dirty working tree. That makes a clean tree useless as a precondition for the automated
  deploy in `TODO.md` item 1.

## [1.6.0] - 2026-09-03

### Added

- `monitoring/vaultwarden-db-backup.sh`: daily consistent copy of the Vaultwarden database at 03:50,
  ten minutes before the restic run. restic mounted `/opt/docker` read-only and copied
  `vaultwarden-data/db.sqlite3` while Vaultwarden was writing to it, and SQLite in WAL mode spreads a
  commit across the database file and the write-ahead log, so a snapshot taken between the two could
  restore into a torn transaction. The dump now goes through SQLite's online backup API into
  `vaultwarden-db-backup/db.sqlite3`, is verified with `PRAGMA integrity_check` and only then
  replaces the previous copy. Any failure keeps the last verified copy and mails. Vaultwarden keeps
  serving, because the backup API takes a read lock per page batch rather than stopping the
  container.
- `monitoring/vps-health.sh`: new `vaultwarden_db_backup` check, critical when the consistent copy is
  missing or older than `DB_BACKUP_MAX_AGE_HOURS` (26). The existing `backup` check only proved that
  a snapshot was taken, never that the database inside it could be restored, and the dump job is
  silent on success, so nothing would otherwise notice it stopping.
- `monitoring/cron.d/vaultwarden-db-backup`: cron entry, journal tag `vaultwarden-db-backup`.
- `docs/vaultwarden.md`: "Master password and KDF" section. Records that the KDF is an account
  property on the Vaultwarden user row and that changing it touches nothing server-side, the
  Argon2id target of 64 MiB / 3 iterations / parallelism 4 and why memory rather than iterations is
  the knob to raise, the order in which the password and the KDF are changed with a verified login in
  between, the password-protected export as the only usable rollback, and the fact that the forced
  re-login is what triggered the September 2026 extension failure. Also records the break-glass gap,
  since the admin token's plaintext lives in the vault that the token would be needed to recover.
- `tests/vaultwarden-db-backup.bats` and a `sqlite3` stub: 11 new cases covering a successful publish,
  file permissions, a missing `sqlite3`, an unreadable source, a failed dump and a dump that fails its
  integrity check. The suite is now 62 cases.

### Changed

- `docs/backup.md` now states that a restore takes the vault from `vaultwarden-db-backup/db.sqlite3`
  rather than from the hot `vaultwarden-data/db.sqlite3`, and documents verifying the restored
  database before trusting it.

### Fixed

- `monitoring/vps-health.sh` reported "Vaultwarden 1.37.2 is behind 1.37.2" and mailed 8 problems for
  a healthy server. Two defects, found by the first real cron run on 2026-09-02.
  - The release lookup scraped the GitHub response for anything version-shaped, which also matched
    the release notes. The 1.37.2 notes mention 2026.8.0, 1.37.1 and 1.37.0, so the comparison value
    became seven lines and `sort -V` picked 2026.8.0. It now reads the `tag_name` value itself, on
    pretty and on compact JSON, accepts an optional `v` prefix, and rejects anything that is not a
    dotted version.
  - A check emitting more than one line turned every extra line into a phantom check with an empty
    status, which was alerted on and written to the state file. Check output is now normalised to
    exactly one tab-separated line by `emit`, and an unrecognised status is reported as a malformed
    check rather than silently treated as a fault.
- `monitoring/vps-health.sh` never removed state records for keys a run no longer produces, so a
  renamed check or a malformed run left records behind forever. Recovery is only detected for keys
  still present in the results, so nothing else would have cleared them.

- `monitoring/vps-health.sh` and `monitoring/vaultwarden-autoupdate.sh` read the web vault version
  instead of the server version. `vaultwarden --version` prints both, and taking the last
  version-shaped number picked up `Web-Vault 2026.7.0`, which sorts above every 1.x release, so the
  drift check would have reported an outdated server as current. Caught on the first live dry run.
  Both now match the `Vaultwarden` line specifically, with a regression test.

## [1.5.0] - 2026-09-01

### Added

- `monitoring/vps-health.sh`: hourly health check covering disk usage, expected containers, restic
  backup age and result, the three public HTTPS endpoints, Caddy, and Vaultwarden version drift.
  Mails only on a fault or a recovery, so a healthy system is silent. Repeat reminders for an
  unchanged problem back off, doubling from one day and capping at 30 days, which costs six mails in
  the first month and one a month afterwards. An escalation, a changed message or a fault that
  returns after recovery alerts immediately instead of waiting out the backoff.
- `monitoring/vaultwarden-autoupdate.sh`: weekly Vaultwarden update every Sunday 03:00, one hour
  before the restic run. Snapshots `vaultwarden-data/` before applying, verifies that
  `vault.sdwa5.org/alive` returns 200 afterwards, and on failure restores the snapshot, pins the
  previous image in `docker-compose.override.yml` and mails an alert. Keeps the newest three
  snapshots. Only Vaultwarden is auto-updated.
- `monitoring/lib.sh`: shared config loading and SMTP delivery through `curl` to
  `smtps://smtp.gmail.com:465`, reusing the Gmail app password Vaultwarden already sends from. The
  password is passed to `curl` through a config file on stdin, so it never appears in the process
  list.
- The two cron jobs watch each other. `vps-health.sh` writes `/var/lib/vps-health/last-run` on every
  run and the weekly job mails if that file is missing or older than two hours. Without this a health
  check that silently stopped would look exactly like a healthy server.
- `monitoring/cron.d/vps-health` and `monitoring/cron.d/vaultwarden-autoupdate`: cron entries with
  output going to the journal under their own tags, so nothing new needs log rotation.
- `tests/`: 41 bats cases plus shellcheck, run by `tests/run.sh` entirely in Docker. Stubs `docker`,
  `docker-compose`, `curl`, `systemctl`, `df` and `hostname`, and drives the clock through
  `FAKE_NOW`, so the full backoff schedule is verified in under a second. First test setup in this
  repository.
- `docs/monitoring.md`: what is checked, the backoff schedule, the mail path, installation, how to
  rehearse an alert, and the limitations of monitoring a host from itself.
- `docs/vaultwarden.md`: client compatibility section and a runbook for "clients broken, web vault
  fine", plus the 2026-09-01 incident record.
- `.env.example`: `MONITOR_SMTP_PASSWORD` and the optional monitoring overrides.

### Changed

- Vaultwarden upgraded from 1.36.0 to 1.37.2 on the VPS. The Bitwarden browser extension and the
  mobile app had stopped logging in while the web vault kept working, because the web vault ships
  with the server and is always version-matched. Upstream requires 1.37.0 for clients 2026.7.0+ and
  1.37.2 for clients 2026.8.0+. The API version string moved from 2025.12.0 to 2026.6.0.
- `README.md`: corrected the Compose requirement. The VPS runs docker-compose v1 (1.29.2) and
  `docker compose` does not exist there, so every documented command now uses `docker-compose`. Added
  the monitoring and tests sections.
- `docs/maintenance.md`: notes that monitoring is now active and points at the second runbook.
  Corrected the `docker compose` invocation and flagged the uncapped logging in
  `docker-compose.projects.yml`.
- `docs/infrastructure.md`: the diagram and the stack overview now include the two cron jobs.
- `docs/vaultwarden.md`: corrected the note claiming SMTP is not configured. It has been configured
  through the admin panel and is stored in `vaultwarden-data/config.json`.

### Fixed

- The Bitwarden browser extension and mobile app could not reach `vault.sdwa5.org`. Not the
  disk-full condition of July 2026: disk was at 30 %, all containers healthy and the last backup
  green throughout. The server was four months behind the auto-updating clients, fixed by the 1.36.0
  to 1.37.2 upgrade.

- The Bitwarden browser extension additionally kept failing after the server upgrade, reporting
  "Invalid master password" for a login the server logged as successful. Cause was stale extension
  storage built against the old server, which survives both a logout and a browser restart. A full
  reinstall cleared it and the extension works on 2026.8.0, so no client is pinned. Confirmed on the
  server by the `GET /api/sync => 200 OK` that every failed attempt was missing. Disabling the
  organization policies was tried on 2026-09-01 and reverted; the upstream symptom in
  [#7635](https://github.com/dani-garcia/vaultwarden/issues/7635) reproduces without them. The full
  triage order is in `docs/vaultwarden.md`.

## [1.4.6] - 2026-07-22

### Added

- `docs/shopware/privacy-tos-review-2026-07-22.md`: in-depth AI-assisted DSGVO/AGB
  compliance review of the live Impressum, Datenschutzerklärung, AGB, and Widerrufsrecht
  CMS pages plus the cookie-consent banner wording — best-effort, not legal advice (a
  professional lawyer review is out of budget). Four independent Opus review passes with
  live web verification of volatile facts (EU ODR platform status, EU-US Data Privacy
  Framework, UK adequacy decision), cross-checked against each other and the org's own
  docs. Flags a repealed-statute citation on the Impressum, undisclosed third-party
  embeds/processors on the Datenschutzerklärung, a self-contradicting Widerrufsrecht
  page, cross-page KSchG inconsistency, and the central open question of whether the
  shop's €0-donation mechanic is legally a gift or a disguised sale.

### Changed

- `docs/shopware/TODO.md`: removed resolved "Privacy + ToS pages" item (the review is
  done — applying its suggested fixes is tracked as a new, separate follow-up item
  pending Obmann/board sign-off); reflowed line-wrap width on several other items.

## [1.4.5] - 2026-07-20

### Fixed

- Cookie banner + footer legal links rendered `/page/cms/Array`. Root cause: 8 corrupted
  sales-channel-scoped `system_config` rows from the 2026-06-29 footer-nav write stored
  `core.basicInformation.{imprint,privacy,tos,revocation,shippingPaymentInfo,contact}Page` (and
  `phone`) as `{"_value": uuid}` instead of a bare string, so `(string)[]` → `"Array"`. Removed the
  corrupted rows; storefront now falls back to the correct bare-UUID null-scope defaults. Verified
  live. (Shop config lives in the DB on the VPS — no repo code changed.)

### Added

- SoundCloud embed on Music/Mixes is now a **click-to-load facade** (consent-gated): no request to
  soundcloud.com until the visitor clicks; consent remembered in first-party `localStorage`. DSGVO/
  TKG-compliant without a plugin.
- `cookie.messageTextPage` snippet override (de-DE + en-GB) with a hardcoded `/Datenschutz/` link,
  guaranteeing the pretty banner link independent of CMS-page SEO URLs.

### Changed

- `docs/shopware/cookie-consent.md`: documented the `/page/cms/Array` root cause + fix, the
  SoundCloud facade, and the settings audit (accept-all OFF, EU/AT rationale); corrected the false
  `frosh/cookieman` reference (no such Shopware plugin — `dmind/cookieman` is TYPO3-only).
- `docs/shopware/content-cms.md`: Music/Mixes SoundCloud noted as facade-gated; legal-page config
  corruption fix recorded.
- `docs/shopware/TODO.md`: removed resolved "Cookie consent" item, renumbered.

## [1.4.4] - 2026-07-18

### Added

- `composer.json`: version manifest for the repo (`sdwa5/sdwa5-vps`, mirrors parent-repo convention)
- `docs/maintenance.md`: disk cleanup runbook from the July 2026 100%-full incident (root-cause hunt, safe wins, log-cap prevention)

### Changed

- `docs/ollama.md`: documented compose profile gating and the July 2026 disk cleanup (models purged, container removed, image pruned) with re-enable steps
- `docs/minecraft.md`: documented `textile_backup` retention (keep 3 / 48 h / ~29.8 GiB) and the caveat that pruning only runs while the server is up — so stale archives linger while the profile is inactive
- `README.md`: Ollama row marked profile-gated; added disk-cleanup pointer

## [1.4.3] - 2026-07-18

### Added

- `docker-compose.yml`: global logging config anchor `x-logging` (json-file, max-size 10m, max-file 3), applied to all services via `logging: *default-logging` — caps container log growth, VCS-tracked instead of host `/etc/docker/daemon.json`

## [1.4.2] - 2026-07-18

### Added

- `docker-compose.yml`: `profiles: ["ollama"]` on the `ollama` service — excluded from default `up`, matches the `minecraft` pattern; frees 22 GB of models and stops reboot auto-resurrect

## [1.4.1] - 2026-07-09

### Changed

- `docs/shopware/content-cms.md`: "Artists & Friends" CMS entry expanded with additional links and descriptions
- `docs/infrastructure.md`: simplified mermaid diagram (no edge port labels, adjusted node spacing), reformatted service table, clarified Ollama port and zswap notes
- `docs/shopware/TODO.md`: reordered and expanded tasks (404/maintenance layouts, cookie config checks, plugin→composer migration)

## [1.4.0] - 2026-07-09

### Added

- `docker-compose.yml`: Vaultwarden `DOMAIN=https://vault.sdwa5.org` — fixes admin diagnostics "Domain configuration No Match / No HTTPS"
- `Caddyfile`: vault.sdwa5.org block sets `header_up X-Real-IP {remote_host}` — fixes admin diagnostics "IP header No Match"
- `docs/vaultwarden.md`: admin token rotation procedure (openssl + argon2)

### Changed

- `VAULTWARDEN_ADMIN_TOKEN` is now an Argon2 PHC hash instead of plaintext; `.env.example` documents generation and quoting
- `CHANGELOG.md`: backfilled missing 1.2.0–1.3.2 entries from commit messages

## [1.3.2] - 2026-07-07

### Fixed

- docs/infrastructure.md: diagram — removed Restic → docker cluster edge (distorted dagre ranking, pushed Shopware into DB column); backup source moved into Restic node label

## [1.3.1] - 2026-07-07

### Fixed

- docs/infrastructure.md: removed redundant port labels from Caddy → container edges (mermaid rendered them inside the Docker cluster; ports already in node labels)

## [1.3.0] - 2026-07-07

### Added

- docs/infrastructure.md: mermaid overview diagram (domains → Caddy → containers, direct public ports, backup flow to Google Drive)

### Fixed

- docs/infrastructure.md: Minecraft runs behind compose profile "minecraft", not commented out (table + notes)

## [1.2.1] - 2026-07-07

### Added

- README.md: explicit docs separation (docs/ = technical how, parent repo docs/ = org-level what/why)

## [1.2.0] - 2026-07-04

### Added

- docs/shopware/ — split by topic: README, admin-api, infrastructure, shop-config, content-cms, merch, cookie-consent, theme, TODO

### Changed

- TODO.md: translated to English, relative links, reordered; shopware items moved to docs/shopware/TODO.md
- docs/shopware/TODO.md: cookie consent prioritized, search item scoped
- README.md: shopware docs link updated

### Removed

- docs/shopware.md (split into docs/shopware/)

## [1.1.0] - 2026-07-03

### Added

- Caddyfile: browser-language auto-redirect — German-language browsers requesting `/` get one-time `302 → /de`, marked by `lang_redirect` cookie (first visit only, root path only)
- `docs/caddy.md`: browser-language redirect section with behavior, `redir` matcher gotcha, curl verification commands
- `docs/shopware.md`: "Languages & domains" section — sales channel domains, URL-based switcher, hreflang decision, en_US decision (not configured), Caddy redirect pointer

### Changed

- `docs/shopware.md`: TODO item 1 (language switching) collapsed to remaining German-homepage issue

## [1.0.1] - 2026-07-02

### Added

- Track Shopware store-installed plugins not covered by composer.lock: FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity, FroshShopmon
- Track Shopware app config: composer.json, composer.lock, symfony.lock, config/packages, config/routes*, config/services.yaml, config/bundles.php
- Track Minecraft server config: server.properties, eula.txt, ops.json, whitelist.json, banned-players.json, banned-ips.json, config/ (mod configs)

### Changed

- `.gitignore`: `shopware-html-data/` and `minecraft-data/` switched from full ignore to allowlist (runtime data, secrets, vendor code stay ignored)

## [1.0.0] - 2026-06-30

### Added

- Initial repository setup from existing live VPS configuration
- `docker-compose.yml` with Shopware, Vaultwarden, Dolibarr SdWa5, Ollama, Restic backup, Minecraft (inactive)
- `docker-compose.projects.yml` with Dolibarr Project 2 and Dolibarr Project 3
- `.env.example` template for required secrets
- `.gitignore` excluding all data directories, secrets, and rclone config
- `docs/` directory with documentation for all services
- Extracted all inline credentials to `.env` variables (previously hardcoded as `${VAR:-secret}` defaults)
