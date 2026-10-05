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
- Data dirs: `dolibarr-documents-data/`, `dolibarr-custom-data/`, `dolibarr-mariadb-data/` and
  `dolibarr-secrets/`, all gitignored. `dolibarr-custom-data/` holds `GeoLite2-Country.mmdb` (MaxMind
  GeoIP DB, re-downloadable) and the custom modules below.

### Custom modules

Custom modules are git checkouts of a tag inside `dolibarr-custom-data/`, which both containers
mount as `/var/www/html/custom`. `tools/dolibarr/deploy-module.sh` installs and updates them on the
VPS as root and hands the checkout to uid 1000, which is `www-data` in the container and `admin` on
the host.

```bash
cd /opt/docker
tools/dolibarr/deploy-module.sh banksync https://github.com/SdWa5/banksync.git v1.2.0
```

A rollback is the same command with the older tag. The script refuses a directory that is not a
checkout, a checkout of another repository, a checkout with local edits and a tag that does not
exist. It never activates anything. After a first install, or after an update that adds scheduled
jobs, boxes or menus, the module is deactivated and activated again in Setup → Modules, because
Dolibarr registers those only on activation.

| Module | Repository | Purpose |
|---|---|---|
| `banksync` | [SdWa5/banksync](https://github.com/SdWa5/banksync), a fork of `vanyolai/dolibarr-banksync` | PayPal sync into bank account 4, automatic posting of the clear cases, a queue with Belege for the rest. The fork's `docs/paypal.md` covers setup and behaviour |

### Module secrets

`dolibarr-secrets/` is mounted read-only as `/run/secrets` into both containers. It holds
credentials that a module reads from a file, so they stay out of the database and every SQL dump
of it. The restic snapshot of `/opt/docker` does include the directory, encrypted, so a restore
brings it back. It is a directory mount because Docker turns a missing file mount into an empty
directory.

| File | Read by | Content |
|---|---|---|
| `paypal.json` | BankSync | `client_id` and `client_secret` of the PayPal Live REST app with Transaction Search, in Vaultwarden as well |

The directory is `0700` and each file `0400`, both owned by `1000:1000`. A file is written by
piping it in, never by typing the secret into a shell command.

```bash
install -d -m 0700 -o 1000 -g 1000 /opt/docker/dolibarr-secrets
# on the workstation, with the JSON in the clipboard:
xclip -selection clipboard -o | ssh root@sdwa5.org 'install -m 0400 -o 1000 -g 1000 /dev/stdin /opt/docker/dolibarr-secrets/paypal.json'
```

Adding a file needs no restart. Creating the directory after the containers started needs
`docker-compose up -d dolibarr dolibarr_cron`, because the bind mount resolves at container start.
The VPS has only the standalone `docker-compose` v1 and no `docker compose` plugin. v1 recreates the
linked `dolibarr_db` along with them, which took ca. 1 minute of ERP downtime on 2026-10-05.

## Project 2 + Project 3 instances

- Inactive (containers not running as of 2026-06-30)
- Defined in `docker-compose.projects.yml`
- No data dirs created yet on VPS
- Start with: `docker-compose -f docker-compose.projects.yml up -d`

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

One record needed only its **town** corrected, from `Elsenwang` to `Hof bei Salzburg`. Elsenwang is a
hamlet inside that municipality and not a postal town, and this record is where the wrong town entered
the documentation in the first place. Which record it is stands in the gitignored
`tools/dolibarr/address-records.json` rather than here, because it is a person.

The organisation's own record was set in the UI on 2026-09-14 and carries the new address, so a
dry run of the script now reports nothing to change anywhere.

**Writing a member also updates the linked user.** Measured on 2026-09-14: the run wrote `members/2`
and then found `users/2` already current, and reading both back confirmed it. Dolibarr propagates
the address from the member to the user it is linked to. The script still visits both, because the
link is a property of those two records rather than a guarantee, and a visit to an already-current
record costs one GET and reports a skip.

## Projects and tasks

The organisation's operational backlog lives in the Projects module rather than in the repositories'
`TODO.md` files, which stay technical. [`tools/dolibarr/sync-pm.sh`](../tools/dolibarr/sync-pm.sh)
rolls it in from a JSON spec.

```bash
tools/dolibarr/sync-pm.sh            # what would change
tools/dolibarr/sync-pm.sh --apply    # write it
```

Dry-run by default and a human starts it, because a write against the live ERP is a production
mutation. That is the same split [`set-address.sh`](../tools/dolibarr/set-address.sh) uses.

**The spec is `tools/dolibarr/pm-spec.json` and it is gitignored.** The real backlog names people and
links private documents, and these repositories are going public.
[`pm-spec.example.json`](../tools/dolibarr/pm-spec.example.json) is the committed shape, and
`DOLIBARR_PM_SPEC` points the script at a different file.

How it matches and what it writes:

- A **project** is matched by its exact `title`, a **task** by its exact `label` within its project.
  Renaming either in the spec creates a second record rather than renaming the first.
- Only the fields an entry names are written. A value set by hand in the UI survives unless the spec
  names that field, so an entry can carry nothing but a title and a task list.
- **Nothing is ever deleted**, and a project the spec does not name is never read or written.
  Dropping an item from the spec leaves the ERP alone, and closing a task stays a UI job.
- A title that differs from an existing one only in case aborts the run. The API offers no way to
  undo the duplicate project it would otherwise create.

### What the API does that the script had to be built around

Read off the Dolibarr 23.0 source and confirmed against the live instance on 2026-09-14 and
2026-09-15. Every one of these was found by a run that was not idempotent.

- `POST /projects` requires `ref` and `title`, `POST /tasks` requires `ref`, `label` and
  `fk_project`. **`ref: "auto"`** makes Dolibarr run its numbering module; `Task::create()` writes a
  null ref for an empty value, so `"auto"` is not optional. A `PUT` validates nothing and takes a
  partial payload.
- **`GET /projects/{id}/tasks` answers an empty list for a project the API user is not a contact
  on**, even for an admin key, and **a project created over this API has no contacts**, because
  `/projects/{id}/contact/{contactid}/{type}` exposes `DELETE` and no `POST`. Measured on
  2026-09-15: project 6 held one task, `GET /tasks` saw it, `GET /projects/6/tasks` returned `[]`,
  and neither validating the project nor switching `usage_task` on changed that. The script
  therefore reads the **global** task list once and filters it by `fk_project`. Assigning a project
  leader remains a UI step, the same class of gap as `/setup/company` being `GET` only.
- **A project created over the API is a draft** (`statut` 0) with `usage_task` 0, where every
  project made in the UI is open with tasks enabled. The script sets `usage_task` on create and
  calls `POST /projects/{id}/validate`, which needs `{"notrigger": 0}` in the body or answers 400
  and names the field.
- A **list endpoint answers an empty collection with a 404 object**, not with an empty array, so
  "no tasks yet" arrives looking like a failure.
- Dolibarr hands numbers back as strings and an unset number back as `null`. Numbers are therefore
  compared numerically and an unset one counts as zero, which is what makes a second run a no-op.
- **Dolibarr HTML-escapes what it stores**, so `Allen & Heath` reads back as `Allen &amp; Heath`.
  Both sides are decoded before they are compared, or a description holding an ampersand would be
  rewritten on every run.

Dates are written as `YYYY-MM-DD` in the spec and stored as epoch seconds.

Measured on 2026-09-15 after the first apply: seven projects, all open with `usage_task` 1, and 23
tasks. A run against that state reports `0 to create, 0 to update, 28 already current`.

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
