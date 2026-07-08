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
cd /opt/docker && docker compose up -d vaultwarden
```

## Notes

- No outbound email configured yet (SMTP not set up) — password reset / invite emails won't work
- Users must be invited or registered via admin panel
