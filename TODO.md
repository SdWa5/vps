1. automatic provisioning and deployment
    1. move credentials from vps to [docs/vaultwarden.md](docs/vaultwarden.md)
    2. github action on merge to main:
        1. pull credentials from vaultwarden
        2. provision vps (idempotent)
        3. deploy to vps (upload from within github action to vps)
        4. cd /opt/docker && docker-compose pull && docker-compose up -d
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
    3. restic copies `vaultwarden-data/db.sqlite3` hot, without a `sqlite3 .backup` step, so a restore
       can hit a torn wal. add a pre-backup hook (ca. 45 Minuten)
    4. no restore drill has ever been run. restore one snapshot into a scratch dir and verify it opens
       (ca. 2 Stunden)
    5. ollama binds `0.0.0.0:11434` with no auth in [docker-compose.yml](docker-compose.yml). profile-
       gated and inactive, but bind it to `127.0.0.1` (ca. 15 Minuten)
    6. monitoring runs on the monitored host, so a dead vps sends nothing and the silence looks
       healthy. an external dead-man's switch would close that gap, deliberately deferred
       (ca. 45 Minuten)
