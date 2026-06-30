# Caddy

Reverse proxy handling TLS termination for all public-facing services.

- Systemd service (NOT in Docker): `systemctl status caddy`
- Config: `/etc/caddy/Caddyfile`
- TLS: Let's Encrypt automatic, email `ripper@sdwa5.org`

## Routing

| Domain                    | Upstream            | Notes                              |
|---------------------------|---------------------|------------------------------------|
| sdwa5.org                 | https://127.0.0.1:8443 | TLS passthrough (skip verify)   |
| vault.sdwa5.org           | http://localhost:8000 |                                  |
| erp.sdwa5.org             | http://localhost:8002 |                                  |
| project2.sdwa5.org     | http://localhost:8003 |                                  |
| project3.sdwa5.org          | http://localhost:8004 |                                  |

## Caddyfile

```
{
    email ripper@sdwa5.org
}

https://sdwa5.org {
    reverse_proxy https://127.0.0.1:8443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}

vault.sdwa5.org {
    reverse_proxy localhost:8000
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
```

## Operations

```bash
systemctl reload caddy     # apply Caddyfile changes (no downtime)
systemctl restart caddy    # full restart
journalctl -u caddy -f    # live logs
```
