# Minecraft

Fabric 1.21.4 server — currently **inactive** (uses Docker Compose profile `minecraft`, excluded from default `up`).

World data persists in `minecraft-data/` on the VPS.

## Configuration (when active)

| Setting          | Value                                 |
|------------------|---------------------------------------|
| Port             | 25565 (public)                        |
| Version          | 1.21.4 (Fabric, auto from mods)       |
| Online mode      | true                                  |
| Difficulty       | 3 (Hard)                              |
| Memory           | 5G                                    |
| Idle timeout     | 10 min                                |
| Whitelist        | bestcodename, Boehmb0Ss, DCXI, NABI   |
| Ops              | bestcodename, Boehmb0Ss               |

## Mods (Modrinth)

`c2me-fabric`, `carpet-extra`, `cloth-config`, `dcintegration` (Discord, 3.1.0.1), `distanthorizons` (beta),
`easyauth`, `fabric-api`, `carpet`, `inventory-sorting`, `lithium`, `scalablelux`, `servux`,
`textile_backup`, `xaeros-minimap`, `xaeros-world-map`

## To start

```bash
docker compose --profile minecraft up -d
```

## Backup retention

The `textile_backup` mod writes world archives to `minecraft-data/backup/world/` (~5.4 GB each). Retention
is already configured in `config/textile_backup.json5` and the mod self-prunes on its own runs:

| Setting | Value | Meaning |
|---------|-------|---------|
| `backupsToKeep` | 3 | keep at most 3 archives |
| `maxAge` | 172800 s | drop archives older than 48 h |
| `maxSize` | 31251200 KiB | ≈ 29.8 GiB folder cap |

**Caveat:** pruning only runs while the server is up. Because Minecraft is profile-gated (inactive), the mod
never runs to age out old archives — so stale backups can sit indefinitely despite the retention config. In
the July 2026 cleanup, 11 GB of May archives were left over this way. Safe to delete manually — Restic mirrors
all of `/opt/docker` off-box daily:

```bash
ls -lht minecraft-data/backup/world/          # newest first
rm minecraft-data/backup/world/<old-archive>.zip
```

See [maintenance.md](maintenance.md).

## Version control

Server config is tracked in the repo: `server.properties`, `eula.txt`, `ops.json`, `whitelist.json`,
`banned-players.json`, `banned-ips.json`, and `config/` (mod configs). `config/Discord-Integration.toml`
stays gitignored — it holds the Discord bot token. `world/`, `backup/`, `mods/`, `logs/`, `versions/`,
`libraries/`, `cache/`, `EasyAuth/easyauth.db` and `DiscordIntegration-Data/` stay gitignored too (runtime
data, or reproducible via `MODRINTH_PROJECTS` in `docker-compose.yml`).
