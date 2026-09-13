1. automatic provisioning and deployment (ca. 16 Stunden)

    today only the vaultwarden **image** updates itself, weekly, via
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
3. [docs/shopware/TODO.md](docs/shopware/TODO.md)
4. maybe add nextcloud (docker-compose.yml)
5. [docs/minecraft.md](docs/minecraft.md)
    1. auto-detect minecraft version from the mods in the modlist (the docker minecraft server in use already has
       this functionality, but it had a bug; that should be fixed by now)
    2. 35 of the 63 tracked files under `minecraft-data/config/` are luckperms translation files,
       downloaded artifacts in 27 languages rather than configuration. every file under
       `minecraft-data/` arrived in one commit, `c516d41`, and none has been edited since, so nothing
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
7. security follow-ups from the 2026-09-07 ssh hardening ([docs/ssh-hardening.md](docs/ssh-hardening.md))
    1. a second copy of `id_ed25519_sdwa5` on the notebook. the key is in vaultwarden since 2026-09-08,
       so the workstation is no longer the only holder, but a rescue console cannot fetch a vault item
       and every client is logged out for a while after a kdf change (ca. 15 Minuten)
    2. one of the three pbkdf2 accounts is in active use and the other two are not. argon2id is
       per-account and only its holder can change it, so this is a message to that person rather than
       an action here. **the per-account figures are deliberately not written down**, here or in
       `sdwa5/docs/services.md`: which account holds how much on the weaker kdf, read beside a
       reachable `vault.sdwa5.org`, names the soft target and prices it. the admin panel has them for
       anybody who should (ca. 15 Minuten)
    3. finish the emergency access enrolment with the new member, in progress since 2026-09-08. the
       sdwa5 org has a single owner, so until a takeover grantee is confirmed, losing that account
       loses the org data. the grantee count is the thing to check in the admin panel; the cipher and
       collection counts are not written down here for the same reason as 7.2 (ca. 30 Minuten)
    4. inbound ipv6 works, including cold after 25 minutes idle, so the neighbour-cache hypothesis is
       refuted. one transient failure on 2026-09-08 was never reproduced and its cause is unknown. do
       not open a contabo ticket. if it recurs, capture the network path in use at the time
       (ca. 10 Minuten)
    5. **DONE on 2026-09-13.** `/opt/docker` had been unable to pull since the 2026-09-12 move: its
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

       **GitHub still holds that public key somewhere neither we nor the API can see**, which is what
       "key is already in use" meant, and deleting the host's copy does not revoke it. It appears on no
       repository in the organization and on no account key. Only GitHub Support can say where it is
       and remove it, and it is worth asking, because a key nobody can account for is a key nobody can
       revoke (`decision`)

       **A history rewrite breaks this again**, because the host's `HEAD` stops existing. The repair is
       `fetch` plus `reset --hard` and never a re-clone, since `/opt/docker` carries the untracked
       runtime state of the whole stack, `minecraft-data` alone being 6.9 GiB. Check the deletions with
       `git diff --name-status HEAD origin/main` first; a tracked file that has since become untracked,
       as `minecraft-data/server.properties` once was, gets removed by the reset whatever `.gitignore`
       says afterwards.
