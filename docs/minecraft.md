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
