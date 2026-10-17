# Caddy

Reverse proxy handling TLS termination for all public-facing services.

- Systemd service (NOT in Docker): `systemctl status caddy`
- Config: `/etc/caddy/Caddyfile`
- TLS: Let's Encrypt automatic, email `ripper@sdwa5.org`, ZeroSSL over ACME as fallback
- Package: `caddy` from the official Caddy apt repository, 2.11.7 since 2026-10-15

## Package and updates

Caddy comes from the official repository at `dl.cloudsmith.io/public/caddy/stable`, not from
Debian. Debian 12 ships 2.6.2-5, built in April 2023 with Go 1.19.8 and never rebuilt, so it lacks
the Go HTTP/2 fixes since then (Rapid Reset, CVE-2023-39325, and the CONTINUATION flood,
CVE-2023-45288). Debian's release notes give Go packages only limited security support.

The key is stored armored as `/usr/share/keyrings/caddy-stable-archive-keyring.asc`, because the
host has no `gpg` to dearmor it. `/etc/apt/sources.list.d/caddy-stable.list` is the upstream
`debian.deb.txt` with its `signed-by` path pointed at that file.

```bash
k=/usr/share/keyrings/caddy-stable-archive-keyring.asc
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key > $k
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  | sed "s#/usr/share/keyrings/caddy-stable-archive-keyring.gpg#$k#" \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -o Dpkg::Options::=--force-confold caddy
```

`--force-confold` keeps the deployed `/etc/caddy/Caddyfile`, which the package lists as a conffile.
Unattended upgrades cover only Debian origins, so a new Caddy release is installed by hand with
`apt-get install caddy`. The upgrade restarts Caddy, which took ca. 5 seconds on 2026-10-15.

**Before an upgrade, check the shops against the new binary.** 2.11 sends the upstream address as
`Host` to an HTTPS upstream, where 2.6.2 passed the client's `Host` through. Shopware picks its
sales channel by `Host`, so both shops answered `400 Sales Channel Not Found` for ca. 45 seconds on
2026-10-15 until the rollback. Both shop blocks now set `header_up Host {host}`. A test instance on
another port does not catch this, because the port in `Host` fails the sales channel lookup on
every version.

Rollback to Debian's package:

```bash
rm /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get download caddy=2.6.2-5
apt-get install --allow-downgrades -o Dpkg::Options::=--force-confold ./caddy_2.6.2-5_amd64.deb
```

## Routing

| Domain                    | Upstream            | Notes                              |
|---------------------------|---------------------|------------------------------------|
| sdwa5.org                 | https://127.0.0.1:8443 | TLS skip verify, client `Host` passed through; de-browser 302→/de (see below) |
| vault.sdwa5.org           | http://localhost:8000 | sets `X-Real-IP` for Vaultwarden; `/admin` 404, HSTS |
| erp.sdwa5.org             | http://localhost:8002 | API explorer 404, HSTS           |
| paper.sdwa5.org           | http://localhost:8006 | `paperless` snippet: `/admin` 404, basic auth 403, HSTS |
| paper.ripper.sdwa5.org    | http://localhost:8007 | same snippet as paper.sdwa5.org |
| chimodiazz.sdwa5.org      | https://127.0.0.1:8444 | TLS skip verify, same shape as sdwa5.org |

## Caddyfile

The config is [`Caddyfile`](../Caddyfile) in the repository root, and `/etc/caddy/Caddyfile` is a
copy of it, not a link. Deploy after `git pull` in `/opt/docker`:

```bash
caddy validate --adapter caddyfile --config /opt/docker/Caddyfile
install -m 644 -o root -g root /opt/docker/Caddyfile /etc/caddy/Caddyfile
systemctl reload caddy
```

`caddy validate` warns that the input is not formatted. That is the file's space indentation and
is harmless.

## Hardening

Each blocked path answers a flat `404` from Caddy and never reaches the container.

| Site | Blocked | Why |
|---|---|---|
| sdwa5.org, chimodiazz.sdwa5.org | `/adminer`, `/mailcatcher`, `/logs` | dockware's development tools, public until 2026-09-15 |
| vault.sdwa5.org | `/admin` | Admin panel, reached through an SSH tunnel instead, see [vaultwarden.md](vaultwarden.md) |
| paper.sdwa5.org, paper.ripper.sdwa5.org | `/admin` | Django admin of Paperless-ngx, used by no client. Any request with HTTP basic auth answers `403`, because basic auth is an unthrottled password oracle there, see [paperless.md](paperless.md#access) |
| erp.sdwa5.org | `/api/index.php/explorer` | Dolibarr's API explorer listed every endpoint. The REST API itself stays public |

`hide_server_headers` strips `Server` and `X-Powered-By` from every live site. Before 2026-10-15
each response carried Caddy's own `Server` header plus the upstream's, for example
`Apache/2.4.58 (Ubuntu)` or `Rocket`.

sdwa5.org sends a `Content-Security-Policy-Report-Only` header on every storefront path, so outside
`/admin`, `/api`, `/store-api` and `/csp-report`. Shopware's storefront template sends no policy of its own,
while the admin sends Shopware's enforcing one, which Caddy leaves alone. The policy allows only the site
itself, plus `data:` for images and fonts. `'unsafe-inline'` stays for scripts and styles, because each page
carries inline scripts without a nonce, so its gain is `object-src`, `base-uri`, `form-action`,
`frame-ancestors` and foreign script hosts, not inline XSS. Browsers report violations to `POST /csp-report`,
which Caddy answers itself with `204` and logs to `/var/log/caddy/sdwa5-csp-report.log` without the client
address and cookies. That log holds only these requests, and it does not contain the report body, so a report
shows that a violation happened and in which browser, not which page or source. Count them with
`wc -l /var/log/caddy/sdwa5-csp-report.log`. Report-only started on 2026-10-18, and switching to the
enforcing `Content-Security-Policy` header is TODO #31.

HSTS is set by Caddy for vault, erp and both Paperless sites with `max-age=31536000`. The two Shopware sites send
`max-age=31536000; includeSubDomains` from the upstream, so Caddy leaves them alone.

`monitoring/security-recheck.sh --external` checks the blocked paths with their bypass variants, the
headers and HSTS, see [monitoring.md](monitoring.md#security-recheck).

## Browser-language redirect (Shopware /de)

German-language browsers (`Accept-Language` starting with `de`) requesting `/` get a one-time
`302 → /de`. Details:

- **Root path only** — deep links are never redirected (English SEO URLs have no automatic `/de`
  equivalent)
- **First visit only** — the redirect response sets `lang_redirect=1` (1 year); requests carrying that
  cookie are never redirected again, so a manual switch back to English sticks. Needed because
  Shopware's language switcher is URL-based and sets no cookie of its own
- Redirect is answered by Caddy directly, never reaches Shopware → no full-page-cache interaction
- Gotcha: `redir /de 302` does NOT work — Caddy parses a leading-`/` first argument as a path
  *matcher*, silently making `302` the target. Must be `redir * /de 302`

Verify after changes:

```bash
# German browser, first visit → 302 /de + Set-Cookie lang_redirect
curl -sI https://sdwa5.org -H 'Accept-Language: de-DE,de;q=0.9'
# German browser, cookie set → 200, no redirect
curl -sI https://sdwa5.org -H 'Accept-Language: de-DE' -H 'Cookie: lang_redirect=1'
# English browser → 200, no redirect
curl -sI https://sdwa5.org -H 'Accept-Language: en-GB,en;q=0.9'
```

## Operations

```bash
systemctl reload caddy     # apply Caddyfile changes (no downtime)
systemctl restart caddy    # full restart
journalctl -u caddy -f    # live logs
```
