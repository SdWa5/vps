# Dolibarr

Three separate Dolibarr instances on the VPS, each with its own MariaDB container.

## Instances

| Instance    | URL                          | Compose file                   | Status   | Company name |
|-------------|------------------------------|--------------------------------|----------|--------------|
| SdWa5       | https://erp.sdwa5.org        | docker-compose.yml             | running  | SdWa5        |
| Project 2 | https://project2.sdwa5.org | docker-compose.projects.yml | inactive | Project 2  |
| Project 3      | https://project3.sdwa5.org     | docker-compose.projects.yml | inactive | Project 3       |

## Credentials

All credentials stored in `/opt/docker/.env`. See `.env.example` for variable names.

Admin login for all instances: `admin` (see `*_ADMIN_PASSWORD` in .env)

## SdWa5 instance

- ERP for Musikverein Schmeiß die Wand an 5
- Cron job runs as separate `dolibarr_cron` container (depends on `dolibarr` being healthy)
- Data dirs: `dolibarr-documents-data/`, `dolibarr-custom-data/`, `dolibarr-mariadb-data/` — all gitignored.
  `dolibarr-custom-data/` currently only holds `GeoLite2-Country.mmdb` (MaxMind GeoIP DB), not custom module
  code — a re-downloadable binary, so it's not tracked in the repo either.

## Project 2 + Project 3 instances

- Inactive (containers not running as of 2026-06-30)
- Defined in `docker-compose.projects.yml`
- No data dirs created yet on VPS
- Start with: `docker compose -f docker-compose.projects.yml up -d`

## Operations

```bash
# Dolibarr SdWa5 logs
docker logs dolibarr
docker logs dolibarr_cron

# DB access (SdWa5)
docker exec -it dolibarr_db mysql -u dolidbuser -p dolidb

# Backup DB manually
docker exec dolibarr_db mysqldump -u root -p dolidb > dolibarr-backup.sql
```
