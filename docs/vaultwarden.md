# Vaultwarden

Bitwarden-compatible self-hosted password manager.

- URL: https://vault.sdwa5.org
- Admin panel: https://vault.sdwa5.org/admin
- Admin token: `VAULTWARDEN_ADMIN_TOKEN` in `/opt/docker/.env` — Argon2 PHC hash, NOT plaintext.
  Plaintext token lives in the admins' password managers; log into `/admin` with the plaintext.
- Data: `vaultwarden-data/`

## Admin token rotation

```bash
# 1. new plaintext token — save it in a password manager first
openssl rand -base64 48
# 2. hash it (argon2 CLI, apt install argon2)
echo -n '<token>' | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
# 3. put hash in /opt/docker/.env, single-quoted (contains $):
#    VAULTWARDEN_ADMIN_TOKEN='$argon2id$...'
# 4. recreate container
cd /opt/docker && docker-compose up -d vaultwarden
```

## Client compatibility — keep the server current

**Vaultwarden must track the Bitwarden client releases.** The browser extension and the mobile app
auto-update from the stores, this server does not. When the server falls behind, those clients stop
working while the web vault keeps going, because the web vault ships with the server and is always
version-matched.

Upstream states the requirement per release, for example
[1.37.0](https://github.com/dani-garcia/vaultwarden/discussions/7473) for clients 2026.7.0+ and
[1.37.2](https://github.com/dani-garcia/vaultwarden/discussions/7615) for clients 2026.8.0+.

This is handled automatically since 2026-09-01. `monitoring/vaultwarden-autoupdate.sh` updates the
container every Sunday and `monitoring/vps-health.sh` warns if the running version ever falls behind
the newest release. See [monitoring.md](monitoring.md).

### Runbook: clients broken, web vault fine

Symptom: the browser extension and the mobile app fail to log in, or log in and show an empty vault,
while https://vault.sdwa5.org works in a normal browser tab.

This is a version mismatch, not an outage. The server is healthy and its API answers correctly.

```bash
# 1. Confirm. The server is up and the API is fine.
curl -sS -o /dev/null -w '%{http_code}\n' https://vault.sdwa5.org/alive        # 200
curl -sS https://vault.sdwa5.org/api/config                                    # valid JSON

# 2. Compare versions.
ssh root@sdwa5.org 'docker exec vaultwarden /vaultwarden --version'
curl -sS https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest | grep tag_name

# 3. Snapshot, then update. Migrations are forward-only, the snapshot is the only way back.
ssh root@sdwa5.org 'cd /opt/docker \
  && docker-compose stop vaultwarden \
  && cp -a vaultwarden-data "vaultwarden-data.bak-$(date +%Y%m%d-%H%M)" \
  && docker-compose pull vaultwarden \
  && docker-compose up -d vaultwarden'

# 4. In the client: restart the browser, then log out and log back in.
#    A stale session can survive a server version jump.
```

If the clients still fail, read their own error rather than guessing. Right-click the extension
icon, Inspect popup, then attempt a login with the Console and Network tabs open, while
`docker logs -f vaultwarden` runs on the server. A request that never reaches the server means the
client aborts locally.

The 2026-09-01 upgrade from 1.36.0 to 1.37.2 moved the API version string from 2025.12.0 to
2026.6.0. See the runbook below for the incident that prompted it.

## Runbook: extension says "Invalid master password" but the server accepted the login

Resolved on 2026-09-02 by reinstalling the extension. Kept here because the diagnosis is not
obvious and the symptom lies about its own cause.

Symptom: the extension reports **"Invalid master password"** or **"no elements in sequence"**, while
the server log says the opposite:

```
[identity][INFO] User <email> logged in successfully. IP: ...
[response][INFO] (login) POST /identity/connect/token => 200 OK
[request][INFO]  POST /identity/accounts/prelogin/password      <- restarts the login flow
```

**The tell is what is missing.** A working login is followed by `GET /api/sync`, `GET
/api/accounts/profile` and a WebSocket upgrade. A broken one goes straight back to
`prelogin/password` and loops. The password is correct and the server served the vault. The client
fails afterwards, while processing the response.

### Triage order

1. **Compare the server and client versions.** Bitwarden clients auto-update from the stores, this
   server does not, and a server left behind breaks them while the web vault keeps working. See the
   section above.
2. **Check whether another client works.** If the mobile app syncs the same vault, the server and the
   account are fine and the fault is in that one client. The app is native and does not run the
   extension's JavaScript paths.
3. **Reinstall the extension.** Remove it in `about:addons`, not disable. Close Firefox completely,
   reopen, reinstall from addons.mozilla.org, set Self-hosted to `https://vault.sdwa5.org` before
   logging in. Stale extension storage survives a logout and a browser restart, so neither of those
   is a substitute.
4. **Only then consider pinning the client** to the last known-good version, currently 2026.7.0, with
   automatic updates off. Upstream tracks the version-specific variant of this symptom as
   [#7635](https://github.com/dani-garcia/vaultwarden/issues/7635),
   [#7632](https://github.com/dani-garcia/vaultwarden/issues/7632) and
   [discussion #7617](https://github.com/dani-garcia/vaultwarden/discussions/7617).

The web vault at https://vault.sdwa5.org is the fallback throughout. It is served by the server, so
it is always version-matched and cannot hit this class of bug.

### Incident 2026-09-01/02

The server ran 1.36.0, built 2026-05-03, four months behind clients that had moved past 2026.7.0.
The extension and, at first, the app could not log in. Disk was at 30 %, every container healthy,
the last backup green.

Two things were needed. Upgrading the server to 1.37.2 was necessary and fixed the app. The
extension kept failing, because it was replaying local state built against the old server, and a
clean reinstall cleared it. It now works on 2026.8.0, so no client is pinned.

What did **not** help, recorded so it is not tried again: logging out inside the extension,
restarting the browser, and disabling the organization policies. The policy attempt came from
#7635 pointing at a date field on policy objects. It was applied and reverted the same evening. The
upstream symptom reproduces with every policy disabled, and all three are `enabled = 1` again.

## Master password and KDF

The KDF is a property of the account, stored on the Vaultwarden user row as `client_kdf_type`,
`client_kdf_iter`, `client_kdf_memory` and `client_kdf_parallelism`. The server never derives
anything from it. It only returns the parameters at `/identity/accounts/prelogin/password` so the
client can turn the master password into the key. **Nothing in this section touches the server.**
There is no environment variable, no compose change, no restart and no Caddy change. It all happens
in the web vault at https://vault.sdwa5.org.

### Target settings

| Setting | Value |
|---------|-------|
| KDF algorithm | Argon2id |
| Memory | 64 MiB |
| Iterations | 3 |
| Parallelism | 4 |

These are Bitwarden's own defaults and they are already a large step up from PBKDF2. Do not raise
the iteration count instead of the memory. Argon2 gains more resistance per unit of unlock time from
memory than from iterations, so a higher `t` at the same memory buys less for the same wait. The
limit on memory is not this server and not the desktop, it is the iOS autofill extension, which runs
under a hard memory ceiling and fails to unlock when the parameters exceed it. Raising memory is
therefore a separate, deliberate change with its own verification on the phone, not something to
bundle into a password rotation.

### Order of operations

Changing the master password and changing the KDF both re-wrap the account key and both revoke every
session on every device. Do them one at a time, with a verified login in between, so a failure names
its own cause.

1. **Export first.** Web vault, Tools, Export vault, format `.json (Encrypted)`, type **Password
   protected**, with a file password that is not the new master password. Store it offline.

   The type matters. **Account restricted** is encrypted with the account key, so it is worthless as
   a rollback if the key change is what went wrong. Only **Password protected** carries its own KDF
   and can be opened without the account.

2. **Consistent server copy.** Run the database backup by hand so the current state is captured
   before anything is re-wrapped:

   ```bash
   ssh root@sdwa5.org /opt/docker/monitoring/vaultwarden-db-backup.sh
   ```

   The stop/snapshot/start dance from the update runbook below is deliberately **not** used here. It
   exists because Vaultwarden migrations are forward-only. A password or KDF change is a single
   atomic request carrying the re-wrapped key, so it cannot half-apply and leave a corrupt database.
   The export in step 1 is the real rollback.

3. **Change the master password.** Web vault, Settings, Security, Master password. Leave "Rotate
   account encryption key" unticked, because that is a third separate operation.

4. **Log back in everywhere and verify**: web vault, browser extension, mobile app. Do not continue
   until all three work.

5. **Change the KDF.** Web vault, Settings, Security, Keys, Encryption key settings, with the values
   from the table above.

6. **Log back in everywhere again**, and verify autofill on the phone specifically. That is the
   setting most likely to break and the one least likely to be noticed.

7. **Clear the generator history last.** A master password generated in the client sits in that
   client's generator history, which anyone who unlocks the vault can read. That is circular, so it
   has to go. It is also the only copy of the password until it has been memorised, so this step
   comes after the new password is committed to memory and demonstrably works, never before.

### The re-login is the risky part, not the change

Steps 4 and 6 force exactly the full re-login that triggered the September 2026 extension failure
recorded below. If the extension reports "Invalid master password" or "no elements in sequence"
afterwards, the vault is almost certainly fine and the extension is replaying stale local state.

**The web vault is the arbiter.** If https://vault.sdwa5.org accepts the new password in a normal
browser tab, the change worked and the fault is in that one client. Follow the reinstall runbook
below rather than assuming the vault is damaged and rolling anything back.

### What a password change does not cover

- **The personal API key is a separate credential.** It lives on the same page, under Settings,
  Security, Keys, and it is not rotated by a master password change. Rotate it there if a client
  secret was ever stored outside the vault.
- **Vault copies already on disk stay readable under the old key forever.** Client state files, old
  desktop or CLI installations and any previous export are unaffected by a password change. They
  have to be deleted. A plaintext export, which is what `bitwarden_export_*.json` is unless the name
  says `encrypted`, is worse than a weak master password and no KDF setting helps against it.
- **Clipboard history.** A password copied out of the vault can persist on disk in the desktop's
  clipboard manager. On KDE that is Klipper, under `~/.local/share/klipper/`.

### Break-glass gap

The admin token's plaintext is documented at the top of this file as living "in the admins' password
managers", and the password manager is this vault. If the vault is unreachable or the master password
is lost, `/admin` is unreachable with it. The recovery path is the offline export from step 1 plus a
restic restore of `vaultwarden-data/`, both of which have to exist before they are needed. Nothing
else closes the loop today.

## Notes

- SMTP is configured through the admin panel and stored in `vaultwarden-data/config.json`. It sends
  as `vault@sdwa5.org` through `smtp.gmail.com` with the `ripper@sdwa5.org` app password. The
  monitoring scripts reuse the same credential, see [monitoring.md](monitoring.md).
- Users must be invited or registered via admin panel.
- Signups are disabled (`signups_allowed: false`).
- The container binds to `127.0.0.1:8000` only. Everything public goes through Caddy.
