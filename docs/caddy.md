# Caddy

Reverse proxy handling TLS termination for all public-facing services.

- Systemd service (NOT in Docker): `systemctl status caddy`
- Config: `/etc/caddy/Caddyfile`
- TLS: Let's Encrypt automatic, email `ripper@sdwa5.org`

## Routing

| Domain                    | Upstream            | Notes                              |
|---------------------------|---------------------|------------------------------------|
| sdwa5.org                 | https://127.0.0.1:8443 | TLS skip verify; de-browser 302→/de (see below) |
| vault.sdwa5.org           | http://localhost:8000 | sets `X-Real-IP` for Vaultwarden |
| erp.sdwa5.org             | http://localhost:8002 |                                  |
| project2.sdwa5.org     | http://localhost:8003 |                                  |
| project3.sdwa5.org          | http://localhost:8004 |                                  |
| chimodiazz.sdwa5.org      | https://127.0.0.1:8444 | TLS skip verify, same shape as sdwa5.org |

## Caddyfile

```
# Global options
{
    email ripper@sdwa5.org  # For Let's Encrypt notifications
}

# Main domain - Shopware
https://sdwa5.org {
    # First-visit browser-language redirect: German browsers land on /de.
    # Only on root path; lang_redirect cookie marks "already redirected once"
    # (Shopware switcher is URL-based, sets no cookie of its own).
    @deFirstVisit {
        path /
        header_regexp Accept-Language ^de
        not header_regexp Cookie (^|;\s*)lang_redirect=
    }
    handle @deFirstVisit {
        header +Set-Cookie "lang_redirect=1; Path=/; Max-Age=31536000; Secure; SameSite=Lax"
        redir * /de 302
    }

    reverse_proxy https://127.0.0.1:8443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}

# Other services
vault.sdwa5.org {
    reverse_proxy localhost:8000 {
        header_up X-Real-IP {remote_host}
    }
}

erp.sdwa5.org {
    reverse_proxy localhost:8002
}

project2.sdwa5.org {
    reverse_proxy localhost:8003
}

project3.sdwa5.org {
    reverse_proxy localhost:8004
}

# chimodiazz.sdwa5.org — Shopware as a CMS, same shape as sdwa5.org above.
# Served a static placeholder from chimodiazz-placeholder/ between 2026-09-15 and
# the first start of the container; that directory is kept, because it is what
# this block falls back to while the instance is down for maintenance.
chimodiazz.sdwa5.org {
    reverse_proxy https://127.0.0.1:8444 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

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
