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
- no mail, no Tika or Gotenberg, and AI features off (TODO #19)

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

## Importing a folder tree

`tools/paperless/upload-tree.sh` uploads existing folders from a workstation as one user. It is a
dry-run by default and keeps no state of its own, because it asks Paperless for each file's SHA-256
checksum first.

```bash
tools/paperless/upload-tree.sh SPEC USER ROOT... > import.dry 2> import.skip   # review
tools/paperless/upload-tree.sh --apply --limit 3 SPEC USER ROOT...             # canary
tools/paperless/upload-tree.sh --apply SPEC USER ROOT... > import.log 2>&1     # the rest
```

- **Ownership.** USER uploads, so USER owns every document and it starts out private. A user with
  TOTP needs a token file made on the host, as above.
- **Tags.** Each folder between ROOT and the file becomes a tag, which is the rule of Paperless's own
  `PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS`, plus `Offen` for a name containing `_OFFEN`. A missing tag is
  created as USER and is private to USER as well.
- **Title and date.** A name `YYYY-MM-DD_rest.ext` with a valid date sets `created` to that date, and
  the title is `rest` with `_` and `-` as spaces and `_OFFEN` dropped. Any other name keeps its
  basename as the title, and Paperless dates the document from its content. Titles are cut to 128
  characters.
- **Skipped.** Junk (`Thumbs.db`, `desktop.ini`, `.DS_Store`, office lock files, Syncthing
  conflicts), names containing `_SENSIBEL` in any case, paths with a tab, newline, `"` or `\`, and
  every type other than PDF, JPEG and PNG. Office files stay out, because both instances run without
  Tika and Gotenberg. Such a file can go in as a PDF made with `soffice --headless --convert-to pdf`.
- **Output.** stdout lists `exists ID SHA256 PATH`, `would-create-tag NAME`,
  `would-upload SHA256 PATH TITLE CREATED TAGS` with the tags joined by `/`, and with `--apply`
  `tag ID NAME` and `uploaded ID SHA256 PATH`. stderr lists `skip REASON PATH`, where a dry-run
  reports a second copy of a file as `duplicate`. All lines are tab-separated.
- **Bandwidth.** One request may take 30 minutes (`PAPERLESS_CURL_TIMEOUT`, default 1800 here),
  because a home uplink measured 36 KB/s, which is ca. 14 minutes for a 30 MB scan. A stopped run
  is simply started again.
- **Resume and verification.** A rerun resumes through the `exists` lines. A dry-run after the
  upload must print no `would-upload`, and its `exists` lines with their hashes are the list of
  originals that are safe to delete, after a `sha256sum --check` where they live.
- **Sharing.** Bulk-add `Haushalt` in the UI to the documents the household should see. The share
  workflow also fires on "Document Updated".

Searching the full text from a workstation, with the token passed on a pipe:

```bash
curl -sfG --config <(printf 'header = "Authorization: Token %s"\n' "$(< PASSWORD_DIR/USER.token)") \
    --data-urlencode 'query=<words>' -d page_size=25 -d fields=id,created,title URL/api/documents/ \
    | jq -r '.results[] | [.id, .created, .title] | @tsv'
```

A hit opens at `URL/documents/<id>/details`.

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

### Restore drill

The household instance holds the only copy of the former Shared Drive "Ripper privat" once its Drive
trash empties on 2026-12-04, so its backup is restored into a throwaway dev mirror and checked by
Paperless itself. Run it from the repository root on the notebook, with `INSTANCE=home` or `sdwa5`
(the DB container is `paperless_<instance>_db`, the media directory `paperless-<instance>-media`):

```
ssh sdwa5.org "DATABASE_BACKUP_CONTAINERS=paperless_${INSTANCE}_db /opt/docker/monitoring/database-backup.sh && find /opt/docker/paperless-${INSTANCE}-media/documents/originals -type f | wc -l"
ssh sdwa5.org 'docker exec restic /bin/sh /opt/restic/backup.sh'   # expect "Backup Successful" and "Forget Successful"

export SDWA5_PAPERLESS_DEV_DIR="$XDG_RUNTIME_DIR/sdwa5-paperless-drill"; D="$SDWA5_PAPERLESS_DEV_DIR/$INSTANCE"; set -o pipefail
tools/paperless/dev-instance.sh up "$INSTANCE" && docker stop "sdwa5-paperless-dev-$INSTANCE"
ssh sdwa5.org "docker exec restic restic dump latest /data/database-backup/paperless_${INSTANCE}_db.tar.gz" | tar -xzO dump.sql \
    | { printf 'DROP DATABASE IF EXISTS paperless;\n'; cat; } \
    | docker exec -i "sdwa5-paperless-dev-$INSTANCE-db" sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb --no-defaults --user=root'
ssh sdwa5.org "docker exec restic restic dump latest /data/paperless-${INSTANCE}-media" | tar -x --strip-components=2 -C "$D/media"
find "$D/media/documents/originals" -type f | wc -l   # must equal the production count above
tools/paperless/dev-instance.sh up "$INSTANCE"
docker exec -u paperless "sdwa5-paperless-dev-$INSTANCE" /command/with-contenv python3 manage.py document_sanity_checker
tools/paperless/dev-instance.sh purge "$INSTANCE" && rmdir "$SDWA5_PAPERLESS_DEV_DIR"
```

- The fresh dump and backup come first, because the nightly pair can miss documents added in between.
- The mirror lives in the `$XDG_RUNTIME_DIR` tmpfs, because the notebook's root is not encrypted and
  deleted documents would stay in its free blocks.
- The drill passes when the originals count matches and the checker reports no `ERROR` and no
  orphaned file. On a finding, keep the mirror and investigate.
- Re-run it quarterly together with the vault drill in [backup.md](backup.md#restore-drill), and after
  a change to the backup path or a Paperless major update.
- It does not test a restore without this host, which needs the restic password from the offline
  vault copies and access to the Shared Drive "SdWa5 Backup" without the service-account key stored
  on the host.

| Date | Instance | Snapshot | Originals | Checker |
|---|---|---|---|---|
| 2026-11-04 | home | `d83b5c67` | 237 of 237 | passed; 3 INFO for documents without OCR text |

## Updates

Both instances pin the same image in `docker-compose.yml`, by tag and digest, written out on each
service because Dependabot cannot edit a YAML anchor. `tests/dependabot.bats` keeps the two equal. A
Paperless minor runs forward-only migrations, so a bump means reading the release notes, running the
mirror against the new image first and taking a fresh dump.
