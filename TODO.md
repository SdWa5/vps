1. [./docs/shopware.md](./docs/shopware.md)
2. automatisches provisioning und deployment
    1. move credentials from vps to vaultwarden
    2. github action on merge to main:
        1. pull credentials from vaultwarden
        2. provision vps (idempotent)
        3. deploy to vps (upload from within github action to vps)
        4. cd /opt/docker && docker-compose pull && docker-compose up -d
3. evtl nextcloud hinzufügen (docker-compose.yml)
4. google drive <-> dolibarr <-> shopware verbinden falls möglich
5. minecraft
    1. modlist in file auslagern um kommentare zu erlauben und dann die deaktivierten mods auskommentieren (aktuell
       müssen deaktiviert mods entfernt werden wodurch man keine übersicht hat)
    2. automatisch minecraft version anhand mods aus modlist ermitteln lassen (der verwendete docker minecraft server
       hat diese funktionalität schon, jedoch hatte sie noch einen bug, dieser sollte inzwischen gefixt sein)
