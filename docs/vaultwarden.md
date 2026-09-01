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

**Incident 2026-09-01.** The server ran 1.36.0, built 2026-05-03, while the clients had moved past
2026.7.0. The extension and the app failed to log in, the web vault worked. Disk was at 30 %, all
containers healthy, backups green. The server was upgraded to 1.37.2, which moved the API version
string from 2025.12.0 to 2026.6.0. That was necessary but not sufficient, see the next section.

## Known issue: extension 2026.8.0 cannot unlock

**Open upstream, no fixed release as of 2026-09-01. The web vault is unaffected.**

Symptom: the extension reports **"Invalid master password"** or **"no elements in sequence"**, while
the server log says the opposite:

```
[identity][INFO] User <email> logged in successfully. IP: ...
[response][INFO] (login) POST /identity/connect/token => 200 OK
[request][INFO]  POST /identity/accounts/prelogin/password      <- restarts the login flow
```

The tell is what is **missing**. A working login is followed by `GET /api/sync`, `GET
/api/accounts/profile` and a WebSocket upgrade. A broken one goes straight back to
`prelogin/password` and loops. The password is correct, the server served it, the client fails
afterwards while processing the response.

Affects extension 2026.8.0 against Vaultwarden 1.37.x. Tracked upstream as
[#7635](https://github.com/dani-garcia/vaultwarden/issues/7635),
[#7632](https://github.com/dani-garcia/vaultwarden/issues/7632) and
[discussion #7617](https://github.com/dani-garcia/vaultwarden/discussions/7617).

### What does not help

- **Upgrading the server.** 1.37.2 is the newest release and is already deployed. No commit on `main`
  since 1.37.2 addresses this.
- **Disabling the organization policies.** Tried on 2026-09-01 and reverted. Issue #7635 points at
  `toSdkPolicyView` calling `toISOString()` on a date Vaultwarden never sends, which suggested an
  empty policy list would avoid the crash. It does not. The bug reproduces with every policy
  disabled.
- **Logging out and back in**, or restarting the browser.

### What works

Pin the client to **2026.7.0**, which upstream confirms is unaffected.

Firefox:

1. https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/versions/
2. Download 2026.7.0 and open the `.xpi` in Firefox. It installs over the newer version.
3. `about:addons` → Bitwarden → Details → **Automatic Updates: Off**, otherwise Firefox puts 2026.8.0
   back.
4. Re-check that setting after the fix lands upstream, then turn updates back on.

Until then the web vault at https://vault.sdwa5.org is the fallback. It is served by the server, so
it is always version-matched and cannot hit this class of bug at all.

## Notes

- SMTP is configured through the admin panel and stored in `vaultwarden-data/config.json`. It sends
  as `vault@sdwa5.org` through `smtp.gmail.com` with the `ripper@sdwa5.org` app password. The
  monitoring scripts reuse the same credential, see [monitoring.md](monitoring.md).
- Users must be invited or registered via admin panel.
- Signups are disabled (`signups_allowed: false`).
- The container binds to `127.0.0.1:8000` only. Everything public goes through Caddy.
