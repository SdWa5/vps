1. automatic provisioning and deployment (ca. 16 Stunden)

    today only the vaultwarden **image** updates itself, daily, via
    [monitoring/vaultwarden-autoupdate.sh](monitoring/vaultwarden-autoupdate.sh). everything in this
    repo, so compose files, monitoring scripts and cron entries, reaches the vps only when someone
    runs `git pull` in `/opt/docker` by hand. a merged commit therefore does nothing until deployed
    manually, which is the same silent-drift class the monitoring work removed for image versions.

    decided on 2026-09-03: push-based github action. a pull-based self-update cron job on the vps was
    the cheaper alternative at ca. 5 Stunden and was considered and rejected, because the action gives
    a deployment record per merge and gated deploys. do not re-open that comparison without a reason.

    1. move credentials from vps to [docs/vaultwarden.md](docs/vaultwarden.md)
    2. github action on merge to main:
        1. pull credentials from vaultwarden
        2. provision vps (idempotent)
        3. deploy to vps (upload from within github action to vps)
        4. cd /opt/docker && docker-compose pull && docker-compose up -d
    3. blocked on 1.1, which is circular: the action needs an ssh deploy key or equivalent to reach
       the vps, and the credentials it would read live in the vault it is deploying. break the loop by
       storing the deploy key as a github secret directly, not via vaultwarden
    4. a config deploy touches every service at once, unlike the vaultwarden image update which
       touches one. it needs the same discipline as
       [monitoring/vaultwarden-autoupdate.sh](monitoring/vaultwarden-autoupdate.sh): health-check
       after apply, and on failure `git reset --hard` to the previous commit plus a loud mail
2. connect google drive <-> [docs/dolibarr.md](docs/dolibarr.md) <-> shopware if possible
    1. **the dolibarr half now has a read path.** [tools/dolibarr/doli.sh](tools/dolibarr/doli.sh)
       reads the rest api with a dedicated api user, see
       [docs/dolibarr.md](docs/dolibarr.md#api-access). shopware's read side is already documented in
       [docs/shopware/admin-api.md](docs/shopware/admin-api.md). what is missing is the drive side and
       a decision on what should actually flow between the three, because "if possible" was never
       turned into a list of records (`decision`, ca. 2 Stunden)
    2. **the write path exists now for person records**, see
       [tools/dolibarr/set-address.sh](tools/dolibarr/set-address.sh). setup values stay a ui job,
       because `/setup/company` is `GET` only, measured against the live instance on 2026-09-14
    3. **the projects and tasks write path exists too**, see
       [tools/dolibarr/sync-pm.sh](tools/dolibarr/sync-pm.sh) and
       [docs/dolibarr.md](docs/dolibarr.md#projects-and-tasks). the backlog is a gitignored json
       spec, because the real one names people and links private documents. the script creates and
       updates and never deletes, so closing a task stays a ui job. what is still missing on this
       side is a read back out, meaning nothing tells anyone that a task got closed in the ui
       (ca. 1 Stunde)
3. [docs/shopware/TODO.md](docs/shopware/TODO.md)
4. maybe add nextcloud (docker-compose.yml)
5. [docs/minecraft.md](docs/minecraft.md)
    1. auto-detect minecraft version from the mods in the modlist (the docker minecraft server in use already has
       this functionality, but it had a bug; that should be fixed by now)
    2. 35 of the 63 tracked files under `minecraft-data/config/` are luckperms translation files,
       downloaded artifacts in 27 languages rather than configuration. every file under
       `minecraft-data/` arrived in one commit and none has been edited since, so nothing
       there is hand-maintained. untracking the translations is cleanup with no security value, and it
       makes the next `git pull` on the host delete them, so it is not free (ca. 15 Minuten)
    3. `ops.json` and `whitelist.json` are tracked and hold **five** distinct Minecraft usernames with
       their UUIDs, not four. counted on 2026-09-13: `bestcodename`, `Boehmb0Ss`, `DCXI`, `Emirgfk`
       and `NABI`, several of them appearing twice with an offline and an online uuid. the same names
       are already in `docker-compose.yml` under `OPS` and `WHITELIST`, which is where the image reads
       them from, so untracking the two json files alone would change nothing. these are pseudonyms
       rather than real names and no credential, so it is a disclosure decision for the owner and not
       a leak. **one of the five reads like a surname with digits in it**, which is the only one worth
       a second look before this is settled (`decision`)
6. reliability follow-ups from the 2026-09-01 monitoring work ([docs/monitoring.md](docs/monitoring.md))
    1. **the mechanism is settled and built** — every image is pinned as of 2026-09-08, see
       [docs/maintenance.md](docs/maintenance.md#image-versions). what is left is the **cadence**: who
       checks for new tags and how often. renovate would open the PRs automatically but needs the
       repos public or a token, so it waits on the go-public work. until then it is a manual window,
       and nothing schedules one (`decision`, ca. 30 Minuten)
    2. the restic backup container runs `lobaro/restic-backup-docker:latest`, whose `latest` tag has
       not been pushed since **2021-05-05**, and whose newest version tag is `1.3.1-0.9.6` from 2020.
       so the image carrying both backups is five years old and unmaintained, and it cannot be pinned
       to anything better. either accept it explicitly or move to a maintained image, which changes
       the backup path and therefore waits on the restore drill below (ca. 2 Stunden)
    3. monitoring runs on the monitored host, so a dead vps sends nothing and the silence looks
       healthy. an external dead-man's switch would close that gap, deliberately deferred
       (ca. 45 Minuten)
    4. **`dolibarr_db` has no consistent dump, only hot files.** `monitoring/cron.d/` holds
       `vaultwarden-db-backup` and nothing equivalent for dolibarr, so restic copies the mariadb data
       directory while the server is writing to it. the only dolibarr dump is the manual one in
       [docs/dolibarr.md](docs/dolibarr.md#operations). vaultwarden got this treatment for a reason
       and dolibarr carries the accounting (ca. 2 Stunden)
7. security follow-ups from the 2026-09-07 ssh hardening ([docs/ssh-hardening.md](docs/ssh-hardening.md))
    1. one of the three pbkdf2 accounts is in active use and the other two are not. argon2id is
       per-account and only its holder can change it, so this is a message to that person rather than
       an action here. **the per-account figures are deliberately not written down**, here or in
       `sdwa5/docs/services.md`: which account holds how much on the weaker kdf, read beside a
       reachable `vault.sdwa5.org`, names the soft target and prices it. the admin panel has them for
       anybody who should (ca. 15 Minuten)
    2. finish the emergency access enrolment with the new member, in progress since 2026-09-08. the
       sdwa5 org has a single owner, so until a takeover grantee is confirmed, losing that account
       loses the org data. the grantee count is the thing to check in the admin panel; the cipher and
       collection counts are not written down here for the same reason as 7.1 (ca. 30 Minuten)
    3. inbound ipv6 works, including cold after 25 minutes idle, so the neighbour-cache hypothesis is
       refuted. one transient failure on 2026-09-08 was never reproduced and its cause is unknown. do
       not open a contabo ticket. if it recurs, capture the network path in use at the time
       (ca. 10 Minuten)
    4. **DONE on 2026-09-13.** `/opt/docker` had been unable to pull since the 2026-09-12 move: its
       `origin` still named the deleted personal repository and its `HEAD` was a pre-rewrite commit
       that existed nowhere. Nothing noticed, because deploys are manual. It now tracks
       `git@github.com:SdWa5/vps.git` at 1.32.0, `git pull --ff-only` succeeds unattended, and all six
       containers stayed up throughout, since the change touched only documentation and no compose
       file, monitoring script or hardening config.

       **Two things had to be fixed before the remote worked, and both are worth keeping.**

       **The organization disallowed deploy keys.** `deploy_keys_enabled_for_repositories` was `false`
       on `SdWa5`, which is GitHub's default for a new organization, so no key could be added to any
       repository in it. A personal repository has no such setting, which is why this only appeared
       after the move. It is now `true`. That is an organization-wide loosening and it is the right
       one here, because the alternative is a personal access token in a file on a public-facing host,
       where a deploy key is read-only and reaches exactly one repository.

       **The old deploy key could not be re-registered.** Deleting the personal repository took its
       deploy key with it, and GitHub then refused the same public key everywhere with
       "key is already in use" although it appears on no repository and on no account we can see. A
       fresh keypair `id_ed25519_sdwa5vps` was generated on the host instead and registered read-only,
       and `/root/.ssh/config` points at it. The dead `id_ed25519_deploy` pair was removed from the host on
       2026-09-13, after checking that nothing referenced it and that its public half was not in
       `authorized_keys`, so it granted no inbound access either.

       **The old key is attached to the soft-deleted repository, and that is the whole of "key is
       already in use".** Diagnosed 2026-09-13 from four observations that one explanation fits: on
       2026-09-13 the key still authenticated and GitHub greeted it `Hi bestcodename/sdwa5-vps!`, which
       is the greeting for a deploy key rather than an account key; that repository answers 404; the key
       is on none of the seven repositories this account can admin and on no account key; and GitHub
       refuses to register it anywhere. A deleted repository is restorable for 90 days, so its record
       and its deploy keys survive the delete while the REST API already reports 404.

       It is **not a security problem**. It is a read-only key on a repository that serves nothing, and
       its only private half was removed from this host on 2026-09-13. The registration lapses on its
       own when the retention window closes, around **2026-12-11**. The test that confirms the
       diagnosis is to try adding fingerprint `SHA256:9cc+0NXJEYRo7xyJ2WeTAFQbE94nDbCap3kgNdX39IU` as a
       deploy key in mid-December; if it is accepted then, this was the cause (`decision`, ca. 5 Minuten)

    5. **Six deleted repositories are still restorable, so the pre-rewrite history is unreachable rather
       than destroyed.** This is the one place the go-public work overstated itself, corrected
       2026-09-13. `bestcodename/sdwa5`, `sdwa5-vps` and `sdwa5-3d` were deleted on 2026-09-12, and
       `SdWa5/docs-old`, `vps-old` and `3d-old` on 2026-09-13. GitHub restores a deleted repository
       within 90 days, so every one of them can be brought back until roughly **2026-12-11**, with the
       private email address in 74 commits and the board members' names in theirs.

       **What the verification actually proved.** Fetching a pre-rewrite SHA from each new repository
       returns `not our ref`, with a control fetch proving the test works. That establishes that the
       live repositories do not serve those objects, which is the risk that mattered, because a reader
       holding an old hash cannot pull it. It does not establish destruction, and "cache cleared" was
       written as though it did.

       **It is not a publication blocker.** Restoring needs owner or organization-admin credentials, so
       there is no route to it from outside. What it does change is the honesty of the claim: for an
       exercise about other people's personal data, "GitHub retains a restorable copy until December"
       is a different sentence from "it is gone". Options are to accept it, to let the window close and
       verify after 2026-12-12, or to ask GitHub Support to purge the six permanently, which is free,
       open-ended in time and releases the deploy key above in the same ticket. See
       <https://github.com/settings/repositories> and the organization's equivalent for what is
       actually being held (`decision`, ca. 20 Minuten)

       **A history rewrite breaks this again**, because the host's `HEAD` stops existing. The repair is
       `fetch` plus `reset --hard` and never a re-clone, since `/opt/docker` carries the untracked
       runtime state of the whole stack, `minecraft-data` alone being 6.9 GiB. Check the deletions with
       `git diff --name-status HEAD origin/main` first; a tracked file that has since become untracked,
       as `minecraft-data/server.properties` once was, gets removed by the reset whatever `.gitignore`
       says afterwards.
8. **the Chimo Diazz deploy cannot install a plugin that is not already in the checkout**
   ([docs/chimodiazz.md](docs/chimodiazz.md)). `monitoring/chimodiazz-deploy.sh` runs
   `plugin:refresh`, `plugin:update`, `theme:compile` and `cache:clear`, and deliberately no
   `composer install`. A theme change therefore deploys itself, while a plugin that
   `chimodiazz/website` requires through composer, or one bought in the Shopware store, has to be
   installed on the host by hand. That breaks the property the rest of this pipeline has, namely that
   the shop's state follows from the repository. Raised on 2026-09-16, when a dark mode plugin came
   up. Dark mode itself belongs in the theme's own scss rather than here.

   Two halves, and they are separate decisions:

    1. composer requires from the plugin. running `composer install` in the container on every deploy
       is the obvious move and the dangerous one, because it reaches the network from a production
       shop, it can fail halfway, and the rollback would have to undo it as well. A safer shape runs
       it only when `composer.lock` moved, behind the same rollback, with the vendor directory
       snapshotted first (ca. 6 Stunden)
    2. store-bought plugins. These come from `packages.shopware.com` through composer, which
       `sdwa5.org` does since 2026-10-01 with its own shop token in an untracked `auth.json`, see
       [docs/shopware/plugins.md](docs/shopware/plugins.md). Chimo Diazz would need the composer
       token of its own shop, and installing it on deploy is then the same question as half 1. What
       is still wanted is a check that alerts when a plugin lands in `custom/plugins/` through the
       admin's plugin manager instead, because that one is locked as a path and not reproducible
       (ca. 4 Stunden)
9. **Chimo cannot see what his own deploy did.** Deployment is a pull from this side, so a push into
    `chimodiazz/website` is handed over and then goes quiet. `monitoring/chimodiazz-deploy.sh` runs
    every five minutes, writes no state file and no log that anything off this host can read, and its
    only output is a mail to the monitoring recipient when a run fails. Read in the script on
    2026-09-17, where those seven `send_mail` calls are the whole of it. His cloud Claude Code session
    therefore has no way to learn which commit is checked out, whether the last `theme:compile`
    succeeded, or why a rollback happened, and the admin API and the `Chimo agent MCP` integration
    reach the shop's data while saying nothing about the deploy. Raised on 2026-09-17.

    **The constraint is that whatever is granted reaches this one instance and nothing else.** A shell
    account is what that rules out, because `/opt/docker` carries every service in this repository. It
    does not rule out SSH itself, which is proposal 1 below. A reader on the monitoring mailbox is
    ruled out as well, because `MONITOR_MAIL_TO` is one address for the whole host and receives the
    health, backup and vaultwarden mails too.

    Four proposals, and they are alternatives rather than steps:

    1. **a forced-command SSH key that can only talk to this instance.** Measured on the host on
       2026-09-17, the ground is favourable. sshd has no `AllowUsers`, no `AllowGroups`, no
       `DenyUsers` and not a single `Match` block, `PasswordAuthentication` is already `no`, the
       `docker` group exists with **zero members** because everything here runs as root, and the only
       human uid is `admin` at 1000 with `/usr/sbin/nologin`. The shape is then a fresh account with
       no password and no `sudo` group membership, his own public key in its `authorized_keys` behind
       `restrict,command="…"`, a `Match User` block that repeats `ForceCommand`, `PermitTTY no` and
       `AllowTcpForwarding no` so that an edited `authorized_keys` cannot widen it, and one
       `/etc/sudoers.d` line naming a single root-owned helper with no wildcard in it.

       **The `docker` group is not the way in and staying out of it is the whole point**, because a
       member of it bind-mounts `/` into a container and is thereby root on this host. The wrapper
       maps a verb out of `SSH_ORIGINAL_COMMAND` onto a fixed `case` and hands the privileged half no
       string it received from the network, and it names `chimodiazz_shopware` and `chimodiazz-src`
       literally, so nothing it can be asked for reaches vaultwarden, dolibarr, minecraft or the
       `sdwa5.org` shop. The verbs worth having are the deploy state, the tail of the last run, a
       `--force` redeploy under the lock the script already takes, and an allowlist of exact
       `bin/console` subcommands.

       This is the only proposal that lets him act rather than only watch, and it opens no new public
       endpoint and puts no token on a public name. What it costs is a shell script parsing a remote
       string, where a quoting bug is root, so it is also the one that has to be written carefully and
       covered by the `tests/` suite. The private half would live wherever his cloud session keeps it,
       which is the weakest part of the arrangement and the reason the scope is drawn this tightly,
       because losing that key should cost the shop and nothing else. Revocation is one line out of
       `authorized_keys`. **Worth doing in the same pass is an `AllowGroups`**, since today any
       account on this host that has a key can log in, and that was acceptable while there was only
       one such account (ca. 6 Stunden)
    2. **a status file that the deploy script writes and Caddy serves.** Each run would record the
       branch, the commit, the timestamp, the outcome and, on a failure, the tail of the command that
       failed, as JSON somewhere under `/opt/docker`, and a `handle` in the `chimodiazz.sdwa5.org`
       block would serve that one path behind a bearer token. It reads nothing outside this instance,
       it opens no port and no account, and an agent can poll it. What it needs deciding first is
       whether commit hashes and build error output are fit to sit behind a single static token on a
       public name, and whether a failing `theme:compile` may quote plugin source. The state file is
       worth building either way, because proposal 1 wants the same data to print (ca. 3 Stunden)
    3. **the same result written back to `chimodiazz/website` as a commit status**, which is where he
       is looking anyway and where an agent reads it without any new endpoint. It costs a token with
       write access to a repository this host does not own, which inverts the read-only direction that
       the pull deployment was chosen for in the first place. That is the reason to expect this one to
       be rejected rather than a detail to solve (ca. 4 Stunden)
    4. **a second recipient for this script alone**, by setting `MONITOR_MAIL_TO` in
       `/etc/cron.d/chimodiazz-deploy` rather than in `.env`, so the deploy mails reach him and the
       rest of the host's monitoring does not. It is the cheapest of the four and it closes the human
       half only, because a mailbox is not something his session reads (ca. 30 Minuten)
10. **add paperless-ngx** (docker-compose.yml, behind Caddy) for two tenants, myself privately and the
    Soundsystem Verein. One instance is the goal and two instances are the fallback. Paperless-ngx has
    had per-object owners and permissions since 1.14, and workflows can set the owner by consume path
    or mail rule, so one instance with a private user and an org user or group should cover it. This
    is from the project docs and not yet tried here. Check before deciding that tags, correspondents
    and document types can be kept apart per owner as well, because a shared vocabulary would leak the
    private side's structure to the org. Backups and the monitoring cron need the new volumes either
    way (ca. 6 Stunden)
    1. maybe fork paperless-ngx into the SdWa5 organization rather than running the upstream image
       unchanged. Nothing asks for a code change yet, so a fork is worth it only once one does,
       because every upstream release then has to be merged by hand (`decision`)
    2. make the fork public. Paperless-ngx is GPL-3.0, and publishing the modified source keeps the
       fork in line with it and with the plan to take all sdwa5 repositories public
11. **BankSync follow-ups** ([docs/dolibarr.md](docs/dolibarr.md#custom-modules)). Live since 2026-10-05 in
    dry run at v1.1.0, account 4 mapped, opening balance 333.40 € matched PayPal, daily job at
    06:00 UTC, queue mail to mail@sdwa5.org
    1. switch on `BANKSYNC_AUTOPOST_ENABLED` after the first real `would_post` decisions were reviewed
