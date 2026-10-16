# Dolibarr

Three separate Dolibarr instances on the VPS, each with its own MariaDB container.

## Instances

| Instance    | URL                          | Compose file                   | Status   | Company name |
|-------------|------------------------------|--------------------------------|----------|--------------|
| SdWa5       | https://erp.sdwa5.org        | docker-compose.yml             | running  | SdWa5        |
| Project 2 | https://project2.sdwa5.org | docker-compose.projects.yml | inactive | Project 2  |
| Project 3      | https://project3.sdwa5.org     | docker-compose.projects.yml | inactive | Project 3       |

## Credentials

The SdWa5 instance gets its credentials as compose file secrets, see the `secrets:` block of
[docker-compose.yml](../docker-compose.yml). Each is a file in `/opt/docker/secrets/` (directory 700,
files 400, root) that the containers see under `/run/sdwa5-secrets/`:

| File | Read by | Variable |
|---|---|---|
| `dolibarr_db_root_password` | `dolibarr_db` | `MYSQL_ROOT_PASSWORD_FILE`, used only on an empty datadir |
| `dolibarr_db_password` | `dolibarr_db`, `dolibarr`, `dolibarr_cron` | `MYSQL_PASSWORD_FILE`, `DOLI_DB_PASSWORD_FILE` |
| `dolibarr_cron_key` | `dolibarr`, `dolibarr_cron` | `DOLI_CRON_KEY_FILE` |
| `dolibarr_admin_init_password` | `dolibarr` | `DOLI_ADMIN_PASSWORD_FILE`, used only on an empty schema |

**The admin password used to log in is in none of these files.** It lives in Vaultwarden, and
Dolibarr keeps only its hash. Until 2026-10-16 `.env` held the live admin password, and it sat in
`docker inspect` and in the environment of every Apache process. The image reads
`DOLI_ADMIN_PASSWORD` only to create the first admin of an empty database, and it falls back to
`admin` when the variable is unset. `dolibarr_admin_init_password` is therefore a random value nobody
knows. An accidental fresh init then creates an admin that nobody can log in as, instead of one with
the default password.

A password is changed in Dolibarr itself, in the Password field of the user's Modify form
(`user/card.php?id=<id>&action=edit`). The **Reinit password** button sets a random password instead.
Saving ends the user's open sessions, so the next request asks for a new login. TODO #28 adds the same
change through the API.

Since 2026-10-16 `MAIN_SECURITY_HASH_ALGO` is `password_hash` (Setup > Other setup, entity 1), so a
new password is stored as a `$2y$` bcrypt hash. Before that, every user had an unsalted md5 hash.
Dolibarr still verifies a 32-character md5 hash under the new setting and does not rehash on login, so
a user moves to bcrypt only by changing the password. The admin moved on 2026-10-16, and the other four
users still have md5. Old hashes also stay in the database dumps and the restic snapshots.

`dolibarr_cron` never reads an admin password, because `DOLI_CRON=1` skips the database init.

The image's `get_env_value` reads a `*_FILE` into a shell variable of its entrypoint. Where values
still end up afterwards:

- `/var/www/html/conf/conf.php` (400 `www-data`) holds the database password, written when the
  container is created.
- `/etc/cron.d/dolibarr` (644) and the command line of `cron_run_jobs.php` hold the cron key.

`monitoring/security-recheck.sh` reports per container whether `docker inspect` or a process
environment still carries a secret, by name only, see [monitoring.md](monitoring.md).

Project 2 and Project 3 still read plain variables from `.env`, which carries no values for them,
see the comment at the top of [docker-compose.projects.yml](../docker-compose.projects.yml).

## SdWa5 instance

- ERP for Musikverein Schmeiß die Wand an 5
- Cron job runs as separate `dolibarr_cron` container (depends on `dolibarr` being healthy)
- Data dirs: `dolibarr-documents-data/`, `dolibarr-custom-data/`, `dolibarr-mariadb-data/` and
  `dolibarr-secrets/`, all gitignored. `dolibarr-custom-data/` holds `GeoLite2-Country.mmdb` (MaxMind
  GeoIP DB, re-downloadable) and the custom modules below.

### Outgoing email

Configure outgoing email under Home → Setup → Emails (`/admin/mails.php`). The SdWa5 instance uses
Google Workspace's IP-authorized relay with these settings:

| Setting | Value |
|---|---|
| Sending method | SMTP/SMTPS socket library |
| SMTP host | `smtp-relay.gmail.com` |
| Port | `465` |
| Authentication | None |
| SMTP username and password | Both empty |
| TLS (SSL) encryption | Yes |
| TLS (STARTTLS) encryption | No |
| Allow self-signed certificates | No |
| Sender for automatic emails | `erp@sdwa5.org` |

Dolibarr 23.0.2's live `core/class/smtps.class.php` calls its STARTTLS negotiation from the
SMTP authentication path. With empty credentials, `sendMsg()` takes the separate HELO path and
skips that negotiation. A test on port 587 with STARTTLS selected and empty credentials was rejected
by Google with SMTP 550. Implicit TLS on port 465 avoids this path and keeps transport encryption
and certificate validation enabled. Google's [relay setup guide](https://support.google.com/a/answer/176600)
lists port 465 as supported. Recheck this behavior before changing the port after a Dolibarr upgrade.

On 2026-10-15, the application accepted the passwordless relay test for delivery and the mailbox
owner confirmed receipt. The owner subsequently confirmed revocation of all three old Gmail app
passwords. The shared [relay notes](monitoring.md#outgoing-email-verification) cover the other senders
and restore precautions.

To validate after a change, click **Test sending**, choose the intended recipient, use a distinct
subject and send one message. Check both the application result and receipt in the destination
mailbox. An accepted SMTP response alone does not prove inbox delivery.

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

The REST API has no route for that, so `tools/dolibarr/module-setup.sh` drives Setup → Modules from a
workstation the way an administrator does. It logs in, follows the switch link the page renders for
the module and reads the page again to confirm the new state. Repeating a command changes nothing.
It targets the dev mirror by default. Production needs its URL and the admin password from the vault,
passed as a file so it never reaches the process list.

```bash
tools/dolibarr/module-setup.sh status PmTools
DOLIBARR_URL=https://erp.sdwa5.org \
DOLIBARR_ADMIN_PASSWORD_FILE=<(bw get password <ERP admin item id>) \
    tools/dolibarr/module-setup.sh enable PmTools
```

A reactivation is `disable` followed by `enable`. `mcp-setup.sh` shares the login helpers in
`tools/dolibarr/lib.sh`.

| Module | Repository | Purpose |
|---|---|---|
| `banksync` | [SdWa5/banksync](https://github.com/SdWa5/banksync), a fork of `vanyolai/dolibarr-banksync` | PayPal sync into bank account 4, automatic posting of the clear cases, a queue with Belege for the rest. The fork's `docs/paypal.md` covers setup and behaviour |
| `pmtools` | [SdWa5/dolibarr-pmtools](https://github.com/SdWa5/dolibarr-pmtools) | REST routes for writing the ticket dictionaries and for closing, canceling and reopening tickets the way the ticket card does, and ticket, project and dictionary tools for the [MCP server](#mcp-server). Needs Dolibarr 24 |

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
`docker compose up -d --no-deps dolibarr dolibarr_cron`, because the bind mount resolves at container
start. The VPS uses Docker CE and the Compose plugin since 2026-10-15. The old standalone v1
recreated the linked database too on 2026-10-05, causing ca. 1 minute of ERP downtime; avoid that
dependency recreation with `--no-deps`. Image upgrades follow the
[maintenance runbook](maintenance.md#sec-05-and-sec-25-maintenance-window).

## Project 2 + Project 3 instances

- Inactive (containers not running as of 2026-06-30)
- Defined in `docker-compose.projects.yml`
- No data dirs created yet on VPS
- Start with: `docker compose -f docker-compose.projects.yml up -d`

## API access

The REST API is used from a workstation, read-only through `tools/dolibarr/doli.sh` and for writes
through the idempotent scripts below. It and the
[MCP server](#mcp-server) are the programmatic ways in; the container is bound to `127.0.0.1:8002` and reachable from outside
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

`doli.sh` does not write on purpose. A write against the live ERP is a production mutation, so it
belongs in its own idempotent script that a human starts, such as
[`sync-pm.sh`](#projects-tasks-and-tickets), which is the split the Shopware work uses as well.
What the core API cannot write gets a route in our own module rather than a workaround over ssh,
which is why [PmTools](#custom-modules) exists. The organisation address under Home → Setup →
Company/Organization is still set in the UI.

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

## Projects, tasks and tickets

The organisation's operational backlog lives in the ERP rather than in the repositories' `TODO.md`
files, which stay technical. [`tools/dolibarr/sync-pm.sh`](../tools/dolibarr/sync-pm.sh) rolls it in
from a JSON spec.

**Tickets carry the backlog since 2026-10-15**, each linked to its project. A ticket's severity is a
priority the UI shows on the card and in the list, from Optional, Low, Normal and High to Urgent and
Blocking. A task has a `priority` column too, but no page of Dolibarr 23.0 displays it, measured
against the live source on 2026-10-15. The script still writes tasks for a spec that names them.

**The ticket type says what kind of work a ticket is**, decided in the triage of 2026-10-16. Three types
were added through PmTools, and one built-in type got a meaning of its own.

| Code | Label | Used for |
|---|---|---|
| `RECURRING` | Dauerauftrag | Work that never finishes, such as the bookkeeping, buying gas and drinks, or the merch lines that keep getting reordered. It stays open and needs no done-criterion |
| `PURCHASE` | Einkauf | Buying equipment or material, and ordering printed items such as mugs or business cards from a supplier. A ticket that may end up built instead of bought stays `OTHER` |
| `COM` | Commercial question | Dolibarr's built-in type, used here for the Verein's own commercial side, meaning the merch range and selling it, not for questions from customers |
| `EVENT` | Veranstaltung | An event that has no project yet, such as deciding whether to take part. Once the Verein commits to it, the event becomes a project and its work goes there |
| `OTHER` | Other | Everything else |

A ticket has one type, so a recurring merch line is `RECURRING` and not `COM`. A blocking line about an
event names the project and its date, for example `Blockiert Krampustek Vol. 2 (PJ2610-0008) am
19.12.2026.`

**A ticket cannot block another ticket in Dolibarr 23.0**, so a dependency is a line in the message.
Tickets have no dependency field, and `ticket/card.php` excludes `ticket` from its own link-to block,
read off the 23.0.2 image on 2026-10-15. The waiting ticket says `Blockiert durch TS… „<subject>“`
and the blocker says `Blockiert TS… „<subject>“`, and how urgent the chain is stays the severity.
Merging two tickets follows the same pattern: the surviving message takes over the text and names the
merged ref, and the merged ticket is closed.

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

- A **project** is matched by its exact `title`, a **task** by its exact `label` and a **ticket** by
  its exact `subject`, both within their project. Renaming any of them in the spec creates a second
  record rather than renaming the first, except for a ticket that names its `ref`.
- A ticket entry with a **`ref`** such as `TS2509-0011` is matched by that ref in whatever project it
  sits. Its `subject` and its project then become fields like any other, so changing the subject
  renames the ticket and listing it under another project moves it. A ref the ERP does not know
  aborts the run, because a ref names an existing ticket.
- A ticket entry carries `subject`, `message`, `severity`, `type`, `category` and `assignee`, and
  `ticket_defaults` at the top of the spec fills in whatever an entry leaves out when the ticket is
  created. An existing ticket gets no defaults, so an entry that only extends a message leaves the
  severity and the assignee set in the UI alone. The message is
  plain text, and the script turns each line break into the `<br>` the ERP stores. Severity, type
  and category are checked against the ERP's ticket dictionaries and the assignee against the user
  logins before anything is written, because Dolibarr stores an unknown code anyway and the UI then
  shows it blank.
- A new ticket with an assignee is created in status 2, Assigned, the status the UI gives an
  assigned ticket. An update touches the status only when the entry names a **`status`** of `open`,
  `closed` or `canceled`. That goes through PmTools, which closes the way the ticket card does with
  `date_close` and the closing trigger. A closed ticket that is wanted canceled, or the other way
  round, is reopened first, and a closed ticket whose fields change is reopened before the change
  and closed after it.
- **`dictionaries`** at the top of the spec maintains ticket dictionary entries, keyed by
  `ticket_types`, `ticket_severities` or `ticket_categories`, each a list of `code`, `label`, `pos`,
  `description`, `active` and `use_default`. An entry is matched by its code and written through
  PmTools before any ticket, so a ticket of the same run can already use a new type. A spec that
  uses neither `status` nor `dictionaries` runs without PmTools, and one that does names the module
  when it is missing.
- Only the fields an entry names are written. A value set by hand in the UI survives unless the spec
  names that field, so an entry can carry nothing but a title and a task list.
- **Nothing is ever deleted**, and a project the spec does not name is never read or written.
  Dropping an item from the spec leaves the ERP alone, and closing a task stays a UI job.
  Closing a ticket is the `status` field above.
- **Every run ends with a read back** of what changed in the ERP outside the spec, since 1.82.0. It
  lists the tickets closed or canceled in the UI whose entry sets no `status`, which a run would
  otherwise only show as `skip`, and the open tickets in the spec's projects that the spec does not
  name. Both lines carry the live ref, so the spec can be brought in line by hand. The section only
  reports. The first run against production on 2026-10-16 found TS2610-0024 and TS2610-0026, both
  closed in the UI on 2026-10-15.
- A title or a ticket subject that differs from an existing one only in case aborts the run. The
  API offers no way to undo the duplicate it would otherwise create.

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
- **A ticket message stores a line break as `<br>` followed by a newline** when it is written in the
  UI or with `PUT`, while `POST /tickets` drops the `<br>` and keeps the newline, both measured on
  2026-10-15. Both forms are reduced to the newline before the comparison.
- `POST /tickets` requires `subject` and `message` and numbers the ticket itself when `ref` is
  empty, so a ticket needs no `"auto"`. `PUT /tickets/{id}` answers with the whole ticket rather
  than with its id. Read off the Dolibarr 23.0 source on 2026-10-15.

Dates are written as `YYYY-MM-DD` in the spec and stored as epoch seconds.

Measured on 2026-09-15 after the first apply: seven projects, all open with `usage_task` 1, and 23
tasks. A run against that state reports `0 to create, 0 to update, 28 already current`.

## MCP server

Dolibarr 24 ships an MCP server in its module `ai` at `/ai/server/mcp_server.php`. It accepts one
API key, sent as `X-API-Key` or `Authorization: Bearer`, and runs every tool as one service user,
so that user's rights are the limit of what a client can do. A tool the user has no right for
fails, and the protocol reports it as `Internal server error` while `dolibarr.log` says
`Permission Denied`. The 24.0.1 core tools cover third parties, products, invoices, orders,
categories and reports, but no tickets, projects or dictionaries. [PmTools](#custom-modules) adds
ten `pm_*` tools for those through the `addMcpTools` hook. They fail with a readable `Error:` text
instead of the bare internal error, and a dictionary write needs an admin or PmTools' own right
5003021, which the `mcp` user does not get by default.

[`tools/dolibarr/mcp-setup.sh`](../tools/dolibarr/mcp-setup.sh) sets it up through the same setup
pages an administrator uses. It creates the service user `mcp` when it is missing, grants it ticket
read, write and manage plus project read for all projects, selects it as `AI_MCP_USER_ID`, enables
`AI_MCP_ENABLED`, generates the key when none exists and finishes with `tools/list`. A rerun keeps
the existing key unless `--rotate-key` is given. The key goes into a mode-600 file and is never
printed.

```bash
tools/dolibarr/mcp-setup.sh                         # dev mirror, key in ~/.local/share/sdwa5-dolibarr-dev/mcp-api-key
tools/dolibarr/mcp-setup.sh --rights 56001,41       # another set of right ids
```

Production needs `DOLIBARR_URL=https://erp.sdwa5.org`, `DOLIBARR_ADMIN_PASSWORD_FILE` pointing at
the admin password, for example `<(bw get password ID)`, and `DOLIBARR_MCP_KEY_FILE` outside the
mirror directory. It ran on the mirror and on production on 2026-10-16. The production key lives in
`~/.config/sdwa5-dolibarr-mcp-key` on the workstation, and Claude Code reaches the server as
`dolibarr-sdwa5` in local scope, with a `headersHelper` that reads the key from that file on every
connect, so the key is in no configuration file.

```bash
claude mcp add-json -s local dolibarr-sdwa5 '{"type":"http","url":"https://erp.sdwa5.org/ai/server/mcp_server.php","headersHelper":"jq -n --rawfile k \"$HOME/.config/sdwa5-dolibarr-mcp-key\" \"{\\\"X-API-Key\\\": (\\$k | rtrimstr(\\\"\\\\n\\\"))}\""}'
```

## Local dev mirror

Module and API work happens on a local copy of this instance, and production receives only a tagged
module release through [`deploy-module.sh`](../tools/dolibarr/deploy-module.sh).
[`tools/dolibarr/dev-instance.sh`](../tools/dolibarr/dev-instance.sh) builds that copy from the
newest archive of `monitoring/database-backup.sh`, with the images `docker-compose.yml` pins.

```bash
tools/dolibarr/dev-instance.sh fetch      # copy the newest production archive over ssh
tools/dolibarr/dev-instance.sh restore    # rebuild the mirror from it, http://localhost:8089/
tools/dolibarr/dev-instance.sh up|down|status
tools/dolibarr/dev-instance.sh api-key    # a local API key for admin
```

The copy holds real member data, so it lives in `~/.local/share/sdwa5-dolibarr-dev` with mode 700
and never in a repository. Before Apache starts, every restore and every `up` sets
`MAIN_DISABLE_ALL_MAILS=1` and disables every scheduled job, and no cron container runs. The mirror
has its own instance key, so secrets that production stored encrypted cannot be decrypted, and a
production API key answers 401 there, which was measured on 2026-10-16. `/run/secrets` is not
mounted, so module credentials such as BankSync's `paypal.json` are absent. The port is bound to
`127.0.0.1` and the database sits on an internal network that only the application joins.

Module checkouts are bind-mounted into `custom/` as working trees, `banksync` from
`../sdwa5-banksync` and `pmtools` from `../sdwa5-pmtools` by default. `SDWA5_DOLIBARR_DEV_MODULES="banksync=… pmtools=…"` sets the list,
and `SDWA5_DOLIBARR_DEV_IMAGE` runs a different application image, for example the next Dolibarr
release before it is rehearsed. Every start removes `install.lock`, so a newer image migrates the copy. 23.0.4 to 24.0.1 migrated
cleanly on 2026-10-16. Logins are the production ones. `dev-instance.sh api-key [LOGIN]` gives a
user, `admin` by default, an API key of the mirror's own in `~/.local/share/sdwa5-dolibarr-dev/api-key`,
which is never the production token file. The scripts take it through their environment:

```bash
DOLIBARR_URL=http://localhost:8089 DOLIBARR_TOKEN_FILE=~/.local/share/sdwa5-dolibarr-dev/api-key \
    tools/dolibarr/sync-pm.sh
```

## Operations

```bash
# Dolibarr SdWa5 logs
docker logs dolibarr
docker logs dolibarr_cron

# DB access (SdWa5)
docker exec -it dolibarr_db mysql -u dolidbuser -p dolidb

# Backup DB manually
monitoring/database-backup.sh
monitoring/database-restore-check.sh dolibarr_db
```
