# Paperless-ngx

Two document archives run on this host. Each is a separate Paperless-ngx instance with its own
application, broker and database.

| | Verein | Household |
|---|---|---|
| URL | https://paper.sdwa5.org | https://paper.ripper.sdwa5.org |
| containers | `paperless_sdwa5`, `paperless_sdwa5_db`, `paperless_sdwa5_broker` | `paperless_home`, `paperless_home_db`, `paperless_home_broker` |
| loopback port | 8006 | 8007 |
| networks | `paper_sdwa5`, internal `paper_sdwa5_db` | `paper_home`, internal `paper_home_db` |
| data | `paperless-sdwa5-{data,media,mariadb-data}/` | `paperless-home-{data,media,mariadb-data}/` |
| secrets | `secrets/paperless_sdwa5_{secret_key,db_password,db_root_password}` | `secrets/paperless_home_{secret_key,db_password,db_root_password}` |

## Why two instances

Measured in the Paperless-ngx 3.3.2 source on 2026-10-16:

- **A superuser sees every object.** In one shared instance, every Verein admin would see private
  household documents.
- **An object without an owner is visible to every user.** Any ingestion path that misses an owner
  would expose a private document to all Verein accounts. In the household instance the same mistake
  reaches only the household.
- **The exporter has no owner filter.** The Verein archive must be handed over in one piece when the
  board changes, which `document_exporter` does for a Verein-only instance.
- **The classifier trains on all documents of an instance.** Private content would shape the
  Verein's suggestions and the other way round.

Both still run on the Verein's VPS. Whoever holds root there, the Contabo panel login or the restic
password can read both.

## Settings

The shared settings sit in the `x-paperless-env` anchor of `docker-compose.yml`:

- one web worker, one task worker and one thread per worker, so OCR cannot starve the shops
- OCR languages `deu+eng`
- no consume folder (`PAPERLESS_CONSUMER_DISABLE`), because no scanner or phone reaches a folder on
  this host
- no self sign-up
- no mail, no Tika or Gotenberg, and AI features off (TODO #20)

Documents arrive by web upload or through a mobile app. The uploader becomes the owner.

The secret key and the database passwords are compose file secrets (row "secrets" above), read
through `PAPERLESS_SECRET_KEY_FILE`, `PAPERLESS_DBPASS_FILE` and MariaDB's `MYSQL_*_FILE`. They are
therefore absent from `docker inspect`, but not from the running processes. The image's s6
`init-env-file` copies each `PAPERLESS_*_FILE` into `/run/s6/container_environment/`, so every
Paperless process carries the value. The MariaDB containers carry none in `mariadbd`'s environment
(measured on prod on 2026-10-16). The database
passwords take effect only when a database is first initialized, so a file must keep the value the
database was created with. The admin passwords are not on the host at all. A `docker exec` starts
outside s6 and gets none of the values, so a `manage.py` command runs through `/command/with-contenv`,
which the image's own wrappers such as `document_exporter` already do.

Measured on the dev mirror on 2026-10-16:

| | Memory |
|---|---|
| application idle | ca. 560 MiB |
| MariaDB idle | ca. 137 MiB |
| valkey idle | ca. 5 MiB |
| application during OCR of a 10-page 300-dpi scan | ca. 1.2 GiB, for 49 s |

## Access

Caddy answers `/admin` (Django admin) with 404 and refuses any request with HTTP basic auth with
403. Paperless answers a right password with "MFA required" and a wrong one with "Invalid
username/password", and basic auth has no throttle. That makes it a password oracle even with
TOTP on. The web login and `/api/token/` stay open. `/api/token/` allows 5 attempts per minute and
asks for a TOTP code once one is enrolled, and it is what the mobile apps use.

Every account turns TOTP on in its profile. The logins live in Vaultwarden with their TOTP seeds and
recovery codes.

## Users, groups and sharing

`tools/paperless/setup.sh` writes groups, users, ownerless shared tags and sharing workflows from a
JSON spec. Its format is [`tools/paperless/paperless-spec.example.json`](../tools/paperless/paperless-spec.example.json).
The real specs name people and stay outside the repository. The script is dry-run by default.

```bash
tools/paperless/setup.sh SPEC            # show what would change
tools/paperless/setup.sh --apply SPEC    # write it
```

A user it creates gets a random password in the spec's `password_dir`, readable by the owner only,
and the password moves from there into Vaultwarden. An existing user's password is never touched.

**Sharing by tag.** Each entry of `shares` becomes a workflow named "Share tag T with group G". It
grants G view and edit rights on every document that carries tag T, both when the document is added
and when it is updated, from every source including Web UI uploads. Paperless' own default for
`sources` leaves the Web UI out. Removing the tag later does **not** take the rights back. That has
to be done in the document's permissions dialog.

**Sharing everything.** A `shares` entry without a `tag` becomes "Share all documents with group G".
It grants G view and edit rights on every document when it is added, whoever uploads it, because a
workflow has no owner filter. The Verein instance uses it for its board under the Verein's policy of
maximum transparency, so the board sees the whole archive. Private papers do not belong in that
instance.

The Verein instance has a break-glass `admin` and personal accounts in group `vorstand`, which
everything is shared with. The household instance has a break-glass `admin`, one account per person, and a group whose
shared tag is `Haushalt`. Everything else stays private to its uploader.

**Proving it.** `tools/paperless/visibility-check.sh SPEC` uploads one private document per user and
one tagged document per member of a tagged share. Then it checks, as each user, that the document
list and the full-text search show exactly the user's own documents plus the shared ones, which is
every document for a member of a share without a tag. The test documents are
deleted and purged from the trash afterwards. It needs the users' passwords before TOTP is enrolled,
or tokens made on the host:

```bash
docker exec -u paperless paperless_sdwa5 /command/with-contenv python3 manage.py drf_create_token USER \
    | awk '{ printf "%s", $3 }' > PASSWORD_DIR/USER.token    # never printed
```

`/command/with-contenv` loads the s6 container environment, which holds `PAPERLESS_SECRET_KEY`. A plain
`docker exec` without it fails with `PAPERLESS_SECRET_KEY is not set`. Both production instances
passed the check on 2026-10-17, and every user saw exactly the expected set.

## Dev mirror

`tools/paperless/dev-instance.sh up|down|status|purge [sdwa5|home]` runs an empty instance from the
production images and shared settings on `127.0.0.1:8106` (sdwa5) or `8107` (home). Its admin
password is generated into `~/.local/share/sdwa5-paperless-dev/<instance>/passwords/admin`, so a spec
copy with `url` and `password_dir` pointed there runs `setup.sh` and `visibility-check.sh` locally.

## Backup and restore

- `monitoring/database-backup.sh` dumps both `*_db` nightly, and the health check watches their age.
- Restic backs up `/opt/docker`, which holds the media directories with the originals and archive
  files.
- After a restore, `docker exec -u paperless paperless_sdwa5 /command/with-contenv python3 manage.py document_sanity_checker`
  compares the files with the database.
- The Verein's archive is handed over with `docker exec -u paperless paperless_sdwa5 document_exporter
  ../export`, which writes into the data volume.

## Updates

Both instances share one image pin, `&paperless-image` in `docker-compose.yml`, by tag and digest. A
Paperless minor runs forward-only migrations, so a bump means reading the release notes, running the
mirror against the new image first and taking a fresh dump.
