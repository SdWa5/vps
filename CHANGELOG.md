# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.0] - 2026-09-01

### Added

- `monitoring/vps-health.sh`: hourly health check covering disk usage, expected containers, restic
  backup age and result, the three public HTTPS endpoints, Caddy, and Vaultwarden version drift.
  Mails only on a fault or a recovery, so a healthy system is silent. Repeat reminders for an
  unchanged problem back off, doubling from one day and capping at 30 days, which costs six mails in
  the first month and one a month afterwards. An escalation, a changed message or a fault that
  returns after recovery alerts immediately instead of waiting out the backoff.
- `monitoring/vaultwarden-autoupdate.sh`: weekly Vaultwarden update every Sunday 03:00, one hour
  before the restic run. Snapshots `vaultwarden-data/` before applying, verifies that
  `vault.sdwa5.org/alive` returns 200 afterwards, and on failure restores the snapshot, pins the
  previous image in `docker-compose.override.yml` and mails an alert. Keeps the newest three
  snapshots. Only Vaultwarden is auto-updated.
- `monitoring/lib.sh`: shared config loading and SMTP delivery through `curl` to
  `smtps://smtp.gmail.com:465`, reusing the Gmail app password Vaultwarden already sends from. The
  password is passed to `curl` through a config file on stdin, so it never appears in the process
  list.
- The two cron jobs watch each other. `vps-health.sh` writes `/var/lib/vps-health/last-run` on every
  run and the weekly job mails if that file is missing or older than two hours. Without this a health
  check that silently stopped would look exactly like a healthy server.
- `monitoring/cron.d/vps-health` and `monitoring/cron.d/vaultwarden-autoupdate`: cron entries with
  output going to the journal under their own tags, so nothing new needs log rotation.
- `tests/`: 41 bats cases plus shellcheck, run by `tests/run.sh` entirely in Docker. Stubs `docker`,
  `docker-compose`, `curl`, `systemctl`, `df` and `hostname`, and drives the clock through
  `FAKE_NOW`, so the full backoff schedule is verified in under a second. First test setup in this
  repository.
- `docs/monitoring.md`: what is checked, the backoff schedule, the mail path, installation, how to
  rehearse an alert, and the limitations of monitoring a host from itself.
- `docs/vaultwarden.md`: client compatibility section and a runbook for "clients broken, web vault
  fine", plus the 2026-09-01 incident record.
- `.env.example`: `MONITOR_SMTP_PASSWORD` and the optional monitoring overrides.

### Changed

- Vaultwarden upgraded from 1.36.0 to 1.37.2 on the VPS. The Bitwarden browser extension and the
  mobile app had stopped logging in while the web vault kept working, because the web vault ships
  with the server and is always version-matched. Upstream requires 1.37.0 for clients 2026.7.0+ and
  1.37.2 for clients 2026.8.0+. The API version string moved from 2025.12.0 to 2026.6.0.
- `README.md`: corrected the Compose requirement. The VPS runs docker-compose v1 (1.29.2) and
  `docker compose` does not exist there, so every documented command now uses `docker-compose`. Added
  the monitoring and tests sections.
- `docs/maintenance.md`: notes that monitoring is now active and points at the second runbook.
  Corrected the `docker compose` invocation and flagged the uncapped logging in
  `docker-compose.projects.yml`.
- `docs/infrastructure.md`: the diagram and the stack overview now include the two cron jobs.
- `docs/vaultwarden.md`: corrected the note claiming SMTP is not configured. It has been configured
  through the admin panel and is stored in `vaultwarden-data/config.json`.

### Fixed

- The Bitwarden browser extension and mobile app could not reach `vault.sdwa5.org`. Not the
  disk-full condition of July 2026: disk was at 30 %, all containers healthy and the last backup
  green throughout. The server was four months behind the auto-updating clients, fixed by the 1.36.0
  to 1.37.2 upgrade.

### Known issues

- Extension 2026.8.0 still cannot unlock against Vaultwarden 1.37.2, reporting "Invalid master
  password" for a login the server logs as successful. Open upstream,
  [#7635](https://github.com/dani-garcia/vaultwarden/issues/7635), with no fixed release and no
  addressing commit on `main`. Clients are pinned to extension 2026.7.0 with auto-update off.
  Disabling the organization policies was tried on 2026-09-01 and reverted, the bug reproduces
  without them. See `docs/vaultwarden.md`.

## [1.4.6] - 2026-07-22

### Added

- `docs/shopware/privacy-tos-review-2026-07-22.md`: in-depth AI-assisted DSGVO/AGB
  compliance review of the live Impressum, Datenschutzerklärung, AGB, and Widerrufsrecht
  CMS pages plus the cookie-consent banner wording — best-effort, not legal advice (a
  professional lawyer review is out of budget). Four independent Opus review passes with
  live web verification of volatile facts (EU ODR platform status, EU-US Data Privacy
  Framework, UK adequacy decision), cross-checked against each other and the org's own
  docs. Flags a repealed-statute citation on the Impressum, undisclosed third-party
  embeds/processors on the Datenschutzerklärung, a self-contradicting Widerrufsrecht
  page, cross-page KSchG inconsistency, and the central open question of whether the
  shop's €0-donation mechanic is legally a gift or a disguised sale.

### Changed

- `docs/shopware/TODO.md`: removed resolved "Privacy + ToS pages" item (the review is
  done — applying its suggested fixes is tracked as a new, separate follow-up item
  pending Obmann/board sign-off); reflowed line-wrap width on several other items.

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
