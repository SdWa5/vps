# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.4.0] - 2026-07-09

### Added

- `docker-compose.yml`: Vaultwarden `DOMAIN=https://vault.sdwa5.org` — fixes admin diagnostics "Domain configuration No Match / No HTTPS"
- `Caddyfile`: vault.sdwa5.org block sets `header_up X-Real-IP {remote_host}` — fixes admin diagnostics "IP header No Match"
- `docs/vaultwarden.md`: admin token rotation procedure (openssl + argon2)

### Changed

- `VAULTWARDEN_ADMIN_TOKEN` is now an Argon2 PHC hash instead of plaintext; `.env.example` documents generation and quoting
- `CHANGELOG.md`: backfilled missing 1.2.0–1.3.2 entries from commit messages

## [1.3.2] - 2026-07-07

### Fixed

- docs/infrastructure.md: diagram — removed Restic → docker cluster edge (distorted dagre ranking, pushed Shopware into DB column); backup source moved into Restic node label

## [1.3.1] - 2026-07-07

### Fixed

- docs/infrastructure.md: removed redundant port labels from Caddy → container edges (mermaid rendered them inside the Docker cluster; ports already in node labels)

## [1.3.0] - 2026-07-07

### Added

- docs/infrastructure.md: mermaid overview diagram (domains → Caddy → containers, direct public ports, backup flow to Google Drive)

### Fixed

- docs/infrastructure.md: Minecraft runs behind compose profile "minecraft", not commented out (table + notes)

## [1.2.1] - 2026-07-07

### Added

- README.md: explicit docs separation (docs/ = technical how, parent repo docs/ = org-level what/why)

## [1.2.0] - 2026-07-04

### Added

- docs/shopware/ — split by topic: README, admin-api, infrastructure, shop-config, content-cms, merch, cookie-consent, theme, TODO

### Changed

- TODO.md: translated to English, relative links, reordered; shopware items moved to docs/shopware/TODO.md
- docs/shopware/TODO.md: cookie consent prioritized, search item scoped
- README.md: shopware docs link updated

### Removed

- docs/shopware.md (split into docs/shopware/)

## [1.1.0] - 2026-07-03

### Added

- Caddyfile: browser-language auto-redirect — German-language browsers requesting `/` get one-time `302 → /de`, marked by `lang_redirect` cookie (first visit only, root path only)
- `docs/caddy.md`: browser-language redirect section with behavior, `redir` matcher gotcha, curl verification commands
- `docs/shopware.md`: "Languages & domains" section — sales channel domains, URL-based switcher, hreflang decision, en_US decision (not configured), Caddy redirect pointer

### Changed

- `docs/shopware.md`: TODO item 1 (language switching) collapsed to remaining German-homepage issue

## [1.0.1] - 2026-07-02

### Added

- Track Shopware store-installed plugins not covered by composer.lock: FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity, FroshShopmon
- Track Shopware app config: composer.json, composer.lock, symfony.lock, config/packages, config/routes*, config/services.yaml, config/bundles.php
- Track Minecraft server config: server.properties, eula.txt, ops.json, whitelist.json, banned-players.json, banned-ips.json, config/ (mod configs)

### Changed

- `.gitignore`: `shopware-html-data/` and `minecraft-data/` switched from full ignore to allowlist (runtime data, secrets, vendor code stay ignored)

## [1.0.0] - 2026-06-30

### Added

- Initial repository setup from existing live VPS configuration
- `docker-compose.yml` with Shopware, Vaultwarden, Dolibarr SdWa5, Ollama, Restic backup, Minecraft (inactive)
- `docker-compose.projects.yml` with Dolibarr Project 2 and Dolibarr Project 3
- `.env.example` template for required secrets
- `.gitignore` excluding all data directories, secrets, and rclone config
- `docs/` directory with documentation for all services
- Extracted all inline credentials to `.env` variables (previously hardcoded as `${VAR:-secret}` defaults)
