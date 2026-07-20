# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.4.5] - 2026-07-20

### Fixed

- Cookie banner + footer legal links rendered `/page/cms/Array`. Root cause: 8 corrupted
  sales-channel-scoped `system_config` rows from the 2026-06-29 footer-nav write stored
  `core.basicInformation.{imprint,privacy,tos,revocation,shippingPaymentInfo,contact}Page` (and
  `phone`) as `{"_value": uuid}` instead of a bare string, so `(string)[]` → `"Array"`. Removed the
  corrupted rows; storefront now falls back to the correct bare-UUID null-scope defaults. Verified
  live. (Shop config lives in the DB on the VPS — no repo code changed.)

### Added

- SoundCloud embed on Music/Mixes is now a **click-to-load facade** (consent-gated): no request to
  soundcloud.com until the visitor clicks; consent remembered in first-party `localStorage`. DSGVO/
  TKG-compliant without a plugin.
- `cookie.messageTextPage` snippet override (de-DE + en-GB) with a hardcoded `/Datenschutz/` link,
  guaranteeing the pretty banner link independent of CMS-page SEO URLs.

### Changed

- `docs/shopware/cookie-consent.md`: documented the `/page/cms/Array` root cause + fix, the
  SoundCloud facade, and the settings audit (accept-all OFF, EU/AT rationale); corrected the false
  `frosh/cookieman` reference (no such Shopware plugin — `dmind/cookieman` is TYPO3-only).
- `docs/shopware/content-cms.md`: Music/Mixes SoundCloud noted as facade-gated; legal-page config
  corruption fix recorded.
- `docs/shopware/TODO.md`: removed resolved "Cookie consent" item, renumbered.

## [1.4.4] - 2026-07-18

### Added

- `composer.json`: version manifest for the repo (`sdwa5/sdwa5-vps`, mirrors parent-repo convention)
- `docs/maintenance.md`: disk cleanup runbook from the July 2026 100%-full incident (root-cause hunt, safe wins, log-cap prevention)

### Changed

- `docs/ollama.md`: documented compose profile gating and the July 2026 disk cleanup (models purged, container removed, image pruned) with re-enable steps
- `docs/minecraft.md`: documented `textile_backup` retention (keep 3 / 48 h / ~29.8 GiB) and the caveat that pruning only runs while the server is up — so stale archives linger while the profile is inactive
- `README.md`: Ollama row marked profile-gated; added disk-cleanup pointer

## [1.4.3] - 2026-07-18

### Added

- `docker-compose.yml`: global logging config anchor `x-logging` (json-file, max-size 10m, max-file 3), applied to all services via `logging: *default-logging` — caps container log growth, VCS-tracked instead of host `/etc/docker/daemon.json`

## [1.4.2] - 2026-07-18

### Added

- `docker-compose.yml`: `profiles: ["ollama"]` on the `ollama` service — excluded from default `up`, matches the `minecraft` pattern; frees 22 GB of models and stops reboot auto-resurrect

## [1.4.1] - 2026-07-09

### Changed

- `docs/shopware/content-cms.md`: "Artists & Friends" CMS entry expanded with additional links and descriptions
- `docs/infrastructure.md`: simplified mermaid diagram (no edge port labels, adjusted node spacing), reformatted service table, clarified Ollama port and zswap notes
- `docs/shopware/TODO.md`: reordered and expanded tasks (404/maintenance layouts, cookie config checks, plugin→composer migration)

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
