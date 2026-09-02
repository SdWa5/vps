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

## Notes

- SMTP is configured through the admin panel and stored in `vaultwarden-data/config.json`. It sends
  as `vault@sdwa5.org` through `smtp.gmail.com` with the `ripper@sdwa5.org` app password. The
  monitoring scripts reuse the same credential, see [monitoring.md](monitoring.md).
- Users must be invited or registered via admin panel.
- Signups are disabled (`signups_allowed: false`).
- The container binds to `127.0.0.1:8000` only. Everything public goes through Caddy.
