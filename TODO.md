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
    3. no restore drill has ever been run. restore one snapshot into a scratch dir and verify
       `vaultwarden-db-backup/db.sqlite3` opens (ca. 2 Stunden)
    4. ollama binds `0.0.0.0:11434` with no auth in [docker-compose.yml](docker-compose.yml). profile-
       gated and inactive, but bind it to `127.0.0.1` (ca. 15 Minuten)
    5. monitoring runs on the monitored host, so a dead vps sends nothing and the silence looks
       healthy. an external dead-man's switch would close that gap, deliberately deferred
       (ca. 45 Minuten)
7. security follow-ups from the 2026-09-07 ssh hardening ([docs/ssh-hardening.md](docs/ssh-hardening.md))
    1. no firewall at all. `iptables -P INPUT ACCEPT` with no rules, so every port a container opens
       is public. fail2ban manages its own chain and does not change that. an nftables default-deny
       with the handful of published ports would (ca. 2 Stunden)
    2. second copy of `id_ed25519_sdwa5` on the notebook. today the workstation is the only holder and
       the contabo console is the only thing behind it (ca. 15 Minuten)
    3. `admin` (uid 1000, full sudo) has a password and no authorized_keys, so it can no longer reach
       the host over ssh. decide whether it gets a key or the account goes away (ca. 20 Minuten)
    4. [docs/services.md](../docs/services.md) in the parent repo says vaultwarden has "currently only
       Stefan". the database holds 4 accounts. reconcile the doc with reality (ca. 15 Minuten)
    5. the other three vaultwarden accounts are on pbkdf2. argon2id is a per-account setting
       that only the account holder can change, so this is a message to them rather than an action
       (ca. 15 Minuten)
