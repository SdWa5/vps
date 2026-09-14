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

## API access

The REST API is used read-only from a workstation, through `tools/dolibarr/doli.sh`. It is the
only programmatic way in; the container is bound to `127.0.0.1:8002` and reachable from outside
the host only through Caddy on `https://erp.sdwa5.org`.

Dolibarr ships the API module **off**. A request against a disabled module answers **HTTP 200**
with the HTML sentence `Module <b>Api</b> must be enabled.`, so a plain status-code check reports
it as healthy. `doli.sh` therefore inspects the body as well and says so in plain words.

Setup, done once in the Dolibarr UI:

1. Home → Setup → Modules → enable **API REST**.
2. Create a dedicated user, **not** `admin`, with only the permissions the reads need, and
   generate its API key in the user card.
3. Put the key in `~/.config/sdwa5-dolibarr-token` with mode 600 and in Vaultwarden. Pipe it
   rather than echo it, for example `xclip -selection clipboard -o > ~/.config/sdwa5-dolibarr-token`.

The key is a client credential and deliberately **not** in `.env.example`: no container reads it,
so it is not a deployment variable. `doli.sh` hands it to curl through a config file on stdin, the
same way `send_mail` in `monitoring/lib.sh` passes the SMTP password, so it never enters the
process list.

```bash
tools/dolibarr/doli.sh status                      # reachability and auth
tools/dolibarr/doli.sh company                     # the organisation record on every invoice
tools/dolibarr/doli.sh get 'thirdparties?limit=5'  # any GET
```

Writing is out of scope on purpose. A write against the live ERP is a production mutation, so it
belongs in its own idempotent script that a human starts, which is the split the Shopware work
uses as well. The organisation address under Home → Setup → Company/Organization is set in the UI.

## Changing the postal address

Three person records carry it and all three are writable over the REST API. The organisation's own
record is **not**: `/setup/company` exposes `GET` only, read off the live instance's
`explorer/swagger.json` on 2026-09-14, so that one is a UI step under Home, Setup,
Company/Organization.

[`tools/dolibarr/set-address.sh`](../tools/dolibarr/set-address.sh) rolls the change through the
three writable ones. Dry-run by default, `--apply` writes, and a human starts it because a write
against the live ERP is a production mutation.

```bash
tools/dolibarr/set-address.sh            # what would change
tools/dolibarr/set-address.sh --apply    # write it
```

Record ids are pinned **and** the surname on the record is verified before anything is written. A
pinned id alone would silently rewrite whoever sits at that id after a merge or a re-import, and a
name lookup alone could match the wrong person. A mismatch aborts the run.

The Example Supplies record needed only its **town** corrected, from `Elsenwang` to `Hof bei Salzburg`.
Elsenwang is a hamlet inside that municipality and not a postal town, and this record is where the
wrong town entered the documentation in the first place.

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
