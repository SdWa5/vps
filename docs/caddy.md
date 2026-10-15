# Caddy

Reverse proxy handling TLS termination for all public-facing services.

- Systemd service (NOT in Docker): `systemctl status caddy`
- Config: `/etc/caddy/Caddyfile`
- TLS: Let's Encrypt automatic, email `ripper@sdwa5.org`

## Routing

| Domain                    | Upstream            | Notes                              |
|---------------------------|---------------------|------------------------------------|
| sdwa5.org                 | https://127.0.0.1:8443 | TLS skip verify; de-browser 302→/de (see below) |
| vault.sdwa5.org           | http://localhost:8000 | sets `X-Real-IP` for Vaultwarden; `/admin` 404, HSTS |
| erp.sdwa5.org             | http://localhost:8002 | API explorer 404, HSTS           |
| project2.sdwa5.org     | http://localhost:8003 |                                  |
| project3.sdwa5.org          | http://localhost:8004 |                                  |
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
| erp.sdwa5.org | `/api/index.php/explorer` | Dolibarr's API explorer listed every endpoint. The REST API itself stays public |

`hide_server_headers` strips `Server` and `X-Powered-By` from every live site. Before 2026-10-15
each response carried Caddy's own `Server` header plus the upstream's, for example
`Apache/2.4.58 (Ubuntu)` or `Rocket`.

HSTS is set by Caddy for vault and erp with `max-age=31536000`. The two Shopware sites send
`max-age=31536000; includeSubDomains` from the upstream, so Caddy leaves them alone.

project2 and project3 have no DNS record and no running service, and are left unchanged.

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
