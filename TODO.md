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
    5. add a github action running `tests/run.sh` on push as well. there is no ci today
       (ca. 45 Minuten)
2. connect google drive <-> [docs/dolibarr.md](docs/dolibarr.md) <-> shopware if possible
3. [docs/shopware/TODO.md](docs/shopware/TODO.md)
4. maybe add nextcloud (docker-compose.yml)
5. [docs/minecraft.md](docs/minecraft.md)
    1. move modlist into a separate file to allow comments, then comment out disabled mods (currently disabled
       mods must be removed entirely, so there is no overview of them)
    2. auto-detect minecraft version from the mods in the modlist (the docker minecraft server in use already has
       this functionality, but it had a bug; that should be fixed by now)
6. reliability follow-ups from the 2026-09-01 monitoring work ([docs/monitoring.md](docs/monitoring.md))
    1. update policy for shopware, dolibarr and mariadb — only vaultwarden auto-updates today. decide
       between auto-update, pinned tags with renovate, or a manual quarterly window (ca. 2 Stunden)
    2. [docker-compose.projects.yml](docker-compose.projects.yml) has no `logging:` on any of its four
       services, so the project2/project3 containers log uncapped. same repeat vector as the july 2026
       disk-full incident. apply the `x-logging` anchor (ca. 20 Minuten)
    3. no restore drill has ever been run, for either backup. restore one restic snapshot into a
       scratch dir and verify `vaultwarden-db-backup/db.sqlite3` opens. the contabo auto backup is a
       second independent copy with 10 daily restore points, found 2026-09-08, and it has never been
       restore-tested either. it restores only as a whole vm (ca. 2 Stunden)
    4. ollama binds `0.0.0.0:11434` with no auth in [docker-compose.yml](docker-compose.yml). profile-
       gated and inactive, but bind it to `127.0.0.1` (ca. 15 Minuten)
    5. monitoring runs on the monitored host, so a dead vps sends nothing and the silence looks
       healthy. an external dead-man's switch would close that gap, deliberately deferred
       (ca. 45 Minuten)
7. security follow-ups from the 2026-09-07 ssh hardening ([docs/ssh-hardening.md](docs/ssh-hardening.md))
    1. a second copy of `id_ed25519_sdwa5` on the notebook. the key is in vaultwarden since 2026-09-08,
       so the workstation is no longer the only holder, but a rescue console cannot fetch a vault item
       and every client is logged out for a while after a kdf change (ca. 15 Minuten)
    2. one vaultwarden account still on pbkdf2 has anything to protect, holding a number of items and
       last seen 2026-09-07. argon2id is per-account and only its holder can change it, so this is a
       message to that person rather than an action here. the other two pbkdf2 accounts hold 0 items
       (ca. 15 Minuten)
    3. finish the emergency access enrolment with the new member, in progress since 2026-09-08. the sdwa5 org
       has a single owner and holds a small number of ciphers, and emergency_access still has zero
       rows, so until a grantee is confirmed, losing stefan's account loses the org data. verify with
       `SELECT COUNT(*) FROM emergency_access;` (ca. 30 Minuten)
    4. inbound ipv6 is intermittent and the cause is unknown. it worked on 2026-09-08 at 0% loss with
       a successful `ssh -6` login, and failed completely an hour earlier from a different mullvad
       relay with `address unreachable` from contabo's router. untested hypothesis is neighbour cache
       expiry, since nothing here emits ipv6 and no AAAA record points at the host. test it by leaving
       v6 idle for an hour and attempting inbound before any outbound packet. do not open a contabo
       ticket on the current evidence (ca. 30 Minuten)
