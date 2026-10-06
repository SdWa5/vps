# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.55.1] - 2026-10-06

### Fixed

- SdWa5Theme 1.1.1. Listing cards no longer carry ca. 250 px of empty boxes. The variant line, the
  description, the unit line and the cheaper-variant line are printed only when the core block renders
  text.
- The main navigation row is hidden below 992 px, where it held only the collapsed navbar's padding and
  border.

## [1.55.0] - 2026-10-06

### Added

- `red-text` colour tokens in SdWa5Theme, `#c41c18` light and `#ff4f4a` dark, because the brand red
  `#e5231f` fails WCAG AA as small text.
- Tests that every colour token a rule uses is defined, and that the hero subtitle is selected by position.
- `docs/shopware/TODO.md` item 15, the empty strip between header and hero, left undecided.

### Changed

- SdWa5Theme 1.1.0. Red replaces the Chimo Diazz cyan as the second accent. Links, tile and share links,
  outline buttons, paging, the footer hotline link and the hero slogan use `red-text`, and hover turns
  green. The top gradient runs from green to red. The `link` and `link-hover` tokens are removed.
- The homepage hero crop focus moved from `50% 45%` to `50% 30%`.
- The homepage tiles are a wrapping flex row with at most three per row and a centred last row, so five
  tiles read 3 + 2. Below 768 px they stack.

### Fixed

- The German hero stats line was green, because the theme found the subtitle by `p[style]` and the
  German slot styles every paragraph inline. The subtitle is now `h1 + p`.

## [1.54.5] - 2026-10-06

### Fixed

- The 1.54.4 entry, the share template comment, its test and `TODO.md` item 13 no longer claim a dropped
  trailing slash on German pages. The page measured, `/de/Hardware/`, does not exist and answers 404
  itself, while real German pages such as `/de/Events/` were shared correctly.

## [1.54.4] - 2026-10-06

### Fixed

- `SdWa5Theme` 1.0.4. The share links carry the URL as it was requested. They shared the technical
  `/navigation/<id>` path on English category pages.

### Changed

- `TODO.md` item 13 notes that the Chimo Diazz share aside probably has the same URL defect.

## [1.54.3] - 2026-10-06

### Fixed

- `SdWa5Theme` 1.0.3. Every core rule that used the SdWa5 green as a text colour, 33 selectors such as the
  offcanvas "Show all categories" link and the active category, uses the readable green, and the offcanvas
  headline and back link use the headline colour instead of the red.

### Changed

- `docs/shopware/theme.md` gives the scan for core rules with brand-coloured text and the exact theme
  update commands, including `theme:compile --active-only`.

## [1.54.2] - 2026-10-06

### Fixed

- `SdWa5Theme` 1.0.2. Two rules of 1.0.1 lost to core selectors of higher or equal specificity, so a 320 px
  phone header still wrapped and the current breadcrumb stayed bright green on the light background. The
  hovered breadcrumb uses the readable green as well.

## [1.54.1] - 2026-10-06

### Fixed

- `SdWa5Theme` 1.0.1. On phones the donation button sits in the header row next to the logo instead of
  wrapping below it, the current breadcrumb uses the readable green on the light background, and the
  share bar no longer covers the right edge of the content between 992 and 1400 px.

## [1.54.0] - 2026-10-06

### Added

- `SdWa5Theme` 1.0.0, the shop's own theme plugin in `shopware-html-data/custom/static-plugins/`, ported
  from the Chimo Diazz theme with the SdWa5 green and red, light and dark colour tokens that the dark mode
  plugin leaves alone, DM Sans, Space Grotesk and JetBrains Mono, and a small graffiti header logo.
- Voluntary donation links to PayPal in the header, the offcanvas menu and the footer, with the URL as the
  theme config field `sdwa5-donation-url`.
- Share links for WhatsApp, Telegram and e-mail, as a bar at the right edge on desktop and a row below the
  content on mobile.
- A full-width homepage hero cropped top and bottom, and the homepage link tiles as a card grid.
- `tools/shopware/set-homepage-sections.sh`, which sets the hero and tiles section classes and the hero's
  full width on the live homepage, dry run by default, with `--revert`.
- `tools/shopware/lib.sh` with the admin API helpers both Shopware scripts share.
- `tests/shopware-theme.bats` and `tests/shopware-homepage-sections.bats`.

### Changed

- Search, the account menu, the currency switcher and an empty cart show only on shop pages, and the header
  cart total is hidden everywhere.
- `tools/shopware/set-address.sh` sources `tools/shopware/lib.sh`.
- `.gitignore` tracks `shopware-html-data/custom/static-plugins/SdWa5Theme/`, and
  `tests/shopware-plugins.bats` allows a path lock only for a tracked static plugin.
- `docs/shopware/theme.md` describes the theme, its dark mode translation, deploy and rollback.
- `docs/shopware/plugins.md`, `infrastructure.md`, `content-cms.md` and the licence section of `README.md`
  cover the theme.
- `TODO.md` and `docs/shopware/TODO.md` gain the theme deploy automation, the Chimo Diazz offcanvas share
  bug, a preview for theme changes and the text wordmark fallback.

### Removed

- `docs/shopware/TODO.md` item 11, hiding the cart UI on content pages, which the theme does.

## [1.53.4] - 2026-10-06

### Fixed

- `TODO.md` and the deploy example in `docs/dolibarr.md` name BankSync v1.2.0, the tag deployed on the VPS.

## [1.53.3] - 2026-10-05

### Removed

- The resolved `TODO.md` follow-ups for BankSync, which are fixed in its 1.1.0, and the queue mail
  recipient, which is set.

## [1.53.2] - 2026-10-05

### Changed

- `TODO.md` item 11 lists the BankSync follow-ups instead of the go-live steps, which are done.

## [1.53.1] - 2026-10-05

### Fixed

- `docs/dolibarr.md` uses `docker-compose`, the only Compose on the VPS, and notes that it recreates
  `dolibarr_db` with the Dolibarr containers.

## [1.53.0] - 2026-10-05

### Added

- `tools/dolibarr/deploy-module.sh`, which installs or updates a Dolibarr custom module as a git
  checkout of a tag and hands it to the web user, with a bats suite running real git.
- Read-only mount of `dolibarr-secrets/` as `/run/secrets` in `dolibarr` and `dolibarr_cron`, for
  credentials a module reads from a file.
- `docs/dolibarr.md` sections on custom modules, the BankSync module and module secrets.
- `docs/backup.md` notes that restic covers `dolibarr-secrets/`.
- `TODO.md` item for the BankSync go-live.

### Changed

- `tests/run.sh` installs git into the bats container and shellchecks the new script.
- `.gitignore` covers `dolibarr-secrets/`.

## [1.52.2] - 2026-10-05

### Changed

- `docs/ssh-hardening.md` records the second copy of `id_ed25519_sdwa5` on stefan-notebook.

### Removed

- The resolved `TODO.md` item for the second copy of `id_ed25519_sdwa5`.

## [1.52.1] - 2026-10-01

### Changed

- `store.shopware.com/swagplatformsecurity` from 4.0.11 to 4.0.16 on `sdwa5.org`.
- `docs/shopware/plugins.md` records how a plugin update runs.

## [1.52.0] - 2026-10-01

### Added

- `packages.shopware.com` as a composer repository in `shopware-html-data/composer.json`, authenticated by the
  shop's composer token in the gitignored `shopware-html-data/auth.json`.
- Exact requires for the nine plugins that were not in composer, namely `frosh/lazy-sizes` 3.2.0,
  `frosh/platform-filter-search` 3.1.0, `frosh/shopmon` 0.2.1, `frosh/tools` 3.9.0, `swag/swag-extension-store`
  4.2.2, `swag/language-pack` 5.58.0, `store.shopware.com/swagplatformsecurity` 4.0.11,
  `store.shopware.com/tcinncopyrightcustom` 1.0.7 and `store.shopware.com/dnestorefrontdarkmode` 4.0.0.
- `tests/shopware-plugins.bats`.

### Changed

- All eleven plugins on `sdwa5.org` install into `vendor/` from Packagist or the Shopware Store. The migration
  ran behind maintenance mode and kept every version.
- `docs/shopware/plugins.md` describes the composer setup, the token and the migration, including the stale
  PHP-FPM realpath cache that made the admin answer 500 until a graceful FPM reload.
- `TODO.md` item 8.2 describes the Store repository as available, and items 10 and 11 are now 9 and 10.
- `docs/shopware/TODO.md` items 10 to 14 are now 9 to 13.

### Fixed

- `frosh/mail-platform-archive` and `frosh/platform-thumbnail-processor` were locked as `dist.type: path` into
  the untracked `custom/plugins/`, so `composer install` on a fresh checkout could not rebuild them. Both are
  locked as Packagist zips at the same versions.
- `docs/shopware/TODO.md` item 6.4 referred to its sibling as 5.3.

### Removed

- The source of `FroshLazySizes`, `FroshPlatformFilterSearch`, `FroshShopmon` and `SwagPlatformSecurity` under
  `shopware-html-data/custom/plugins/` (166 files), and the `.gitignore` lines that tracked it.
- `TODO.md` item 9 and `docs/shopware/TODO.md` item 9, both done by this release.

## [1.51.0] - 2026-10-01

### Added

- `FETCH_GRACE` in `monitoring/chimodiazz-deploy.sh`, 900 seconds by default. A fetch that fails is only
  logged until it has failed for that long, since one failed run on 2026-09-29 at 16:55 mailed an alert
  between two good runs.
- Reminders for a remote that stays unreachable, after 1, 2, 4, 8 and 16 days and then every 30 days, and
  one mail when the fetch works again. The state is kept in `/var/lib/vps-health/chimodiazz-deploy-remote`.

### Changed

- The fetch failure mail and the journal carry git's own output instead of discarding it.
- `backoff_seconds` moved from `monitoring/vps-health.sh` into `monitoring/lib.sh`, so both scripts back off
  on the same schedule.

### Fixed

- A branch deleted from `chimodiazz/website` sent the fetch failure mail, which blames the deploy key,
  because git only names a missing branch in a failed fetch. It now sends the branch gone mail at once. The
  fetch runs under `LC_ALL=C`, since the host's git answered in German over SSH.

## [1.50.1] - 2026-09-30

### Fixed

- `docs/ssh-hardening.md` described the outbound key as it stood before 2026-09-15. The `/root/.ssh/config`
  block named `id_ed25519_deploy`, while the host pins `id_ed25519_sdwa5vps_20260915`, and the text said a
  superseded private key was still on disk. Measured on 2026-09-30, `/root/.ssh/` holds only the two deploy
  keys, which matches the deletion recorded further down the same page.

## [1.50.0] - 2026-09-30

### Added

- TODO item 11: paperless-ngx behind Caddy for two tenants, a private one and the Verein. One
  instance with per-owner permissions is the goal and two instances are the fallback. Whether tags,
  correspondents and document types can be separated per owner is still to be checked.
- Sub-items to maybe fork paperless-ngx into the SdWa5 organization and to make that fork public.

## [1.49.0] - 2026-09-17

### Added

- TODO item 10: the deploy is a pull, so Chimo gets nothing back from it. `chimodiazz-deploy.sh`
  writes no state file and no log that anything off this host can read, and its only output is a
  mail to `MONITOR_MAIL_TO`, which is the whole host's monitoring address. His cloud Claude Code
  session can therefore not tell which commit is checked out or why a rollback happened. Four
  alternatives are recorded under the constraint that whatever is granted reaches this one instance
  and nothing else, namely a forced-command SSH key, a token-protected status file served by Caddy, a
  commit status written back to `chimodiazz/website`, and a second mail recipient for this script
  alone.
- The SSH proposal is written against the host as measured on 2026-09-17. sshd carries no
  `AllowUsers`, no `AllowGroups`, no `DenyUsers` and no `Match` block, `PasswordAuthentication` is
  already `no`, the `docker` group has zero members, and the only human uid is `admin` at 1000 with
  `/usr/sbin/nologin`. The proposal is an account with no password and no `sudo` group membership, a
  `restrict,command="…"` key, a `Match User` block that cannot be widened from `authorized_keys`, and
  one wildcard-free `sudoers.d` line for a root-owned helper. Membership of the `docker` group is
  ruled out in writing, because it is equivalent to root on this host.
- [docs/ssh-hardening.md](docs/ssh-hardening.md) records the missing account allowlist as an open
  item, since a second account is what makes it matter.
- [docs/chimodiazz.md](docs/chimodiazz.md) now names the deploy result as something he cannot reach,
  in the table that lists the rest of his access.

## [1.48.0] - 2026-09-16

### Added

- **An admin integration on `chimodiazz.sdwa5.org`, so that machine access stops running on a human's
  credentials.** `Chimo agent MCP` is what `@shopware-ag/admin-mcp` connects with, its client id and
  secret live in the `SSD` Vaultwarden collection next to the login, and
  [docs/chimodiazz.md](docs/chimodiazz.md) carries the `mcpServers` block that uses them. Verified on
  creation with a `client_credentials` grant answering 200 and `GET /api/_info/version` answering
  `6.7.11.1`.

### Removed

- TODO item 10, because its first half is done and its second half is a standing decision rather than
  a task. That the database and the host stay closed, and why, is stated in
  [docs/chimodiazz.md](docs/chimodiazz.md) where the rest of Chimo's access is.

## [1.47.0] - 2026-09-16

### Added

- **[docs/chimodiazz.md](docs/chimodiazz.md) now states what Chimo can reach and what he cannot**, as
  a measured table rather than as something a reader has to assemble from the Caddy snippet and the
  published ports. He is a full administrator in the admin UI and through the password grant of the
  Admin API. MySQL is not published at all, there is no SSH account, and the dockware tools stay
  blocked.
- TODO item 10, marked high priority: his agent cannot use `@shopware-ag/admin-mcp`, because that
  needs an admin integration and his instance has none. The eight integrations it does have are
  Shopware's own service ones with `admin = 0`. Until there is one, machine access runs on a human
  user's credentials.
- The same item records that database access stays out deliberately, because granting it means
  publishing 3306 or handing out an SSH account on this host.

## [1.46.0] - 2026-09-16

### Added

- **[docs/shopware/plugins.md](docs/shopware/plugins.md), the measured inventory of what the live
  shop actually runs.** Eleven plugins are installed and active. Two are `composer.json` requires,
  four are tracked here as source, and **five are recorded nowhere at all**, because `.gitignore`
  ignores `shopware-html-data/custom/plugins/*` and lifts exactly four directories back out of that
  exclusion. Anything installed since falls out of the repository silently.
- The page also records where composer puts a Shopware plugin on this host, which is
  `custom/plugins/<PluginName>/` and not `vendor/`. Measured, because
  `vendor/frosh/mail-platform-archive` holds zero files while the `plugin` table gives that plugin
  `path = custom/plugins/FroshPlatformMailArchive/` with `managed_by_composer = 1`. The directory
  listing cannot tell the two apart and that column can.
- The declared licence of all four vendored plugins, which is MIT in each case. That is the
  measurement behind the carve-out for `shopware-html-data/` in the licence decision.
- TODO item 9 for the migration to composer, split into the six plugins Packagist carries at exactly
  the running version and the three it does not, the latter blocked on a Shopware account token.

### Fixed

- **`docs/shopware/infrastructure.md` named six plugins and implied that was all of them**, and
  `docs/infrastructure.md` repeated the same partial list. Both now point at the inventory instead,
  so one file holds the answer rather than three holding pieces of it.

## [1.45.0] - 2026-09-16

### Added

- **A commit that changes no file the container reads no longer rebuilds the storefront.**
  `monitoring/chimodiazz-deploy.sh` now compares the old and the new commit against
  `REBUILD_PATHS`, which defaults to `shopware/`, and skips `plugin:refresh`, `theme:compile` and
  `cache:clear` when nothing there moved. The checkout still follows every commit, so the next real
  change is built from the right base. `--force` rebuilds regardless, `REBUILD_PATHS=` turns the
  filter off, and a diff that cannot be computed counts as "rebuild", because compiling for nothing
  costs twenty seconds while skipping a real theme change leaves the site stale and says nothing.
- **A failed `cache:clear` is retried once before the deploy gives up and rolls back.** The retry
  empties `var/cache/prod_*` and asks again. A second failure is still a failure.

### Changed

- **The deploy takes its own `flock` instead of being wrapped in one by cron**, on
  `/run/lock/chimodiazz-deploy.lock`, and `monitoring/cron.d/chimodiazz-deploy` calls the script
  directly. Manual maintenance against the same container can now take the same lock, which a
  wrapper in the cron line made impossible: a second `flock` on that file would have contended with
  the one its own parent already held.
- The storefront of `chimodiazz.sdwa5.org` serves `de-DE` by default, with `en-GB` at
  `https://chimodiazz.sdwa5.org/en`. That is sales channel configuration rather than repository
  state, and it is recorded in [docs/chimodiazz.md](docs/chimodiazz.md) so the next reader does not
  have to guess where the language comes from.

### Fixed

- **`ChimodiazzTheme` was installed and activated but never assigned to the sales channel**, so
  every deploy ran cleanly and changed nothing visible. Measured on 2026-09-16 in
  `theme_sales_channel`, which paired the Storefront channel with the default `Storefront` theme.
  `theme:change --all ChimodiazzTheme` fixed it, and the storefront now carries the theme's own
  marker and its three accent colours.
- **Two `cache:clear` runs at once broke a deploy on 2026-09-16.** Symfony builds a fresh cache
  directory and swaps it in, so the loser was left with a half-built directory and a router that
  could not find `url_matching_routes.php`. The deploy rolled back a commit that had only changed
  Markdown. The retry above and the lock in the script are the two halves of the answer.

## [1.44.0] - 2026-09-15

### Added

- **A theme change in chimodiazz/website reaches the live site without anyone touching this host.**
  `monitoring/chimodiazz-deploy.sh` runs every five minutes under its own `flock`, fetches the
  checkout's branch, and when the commit moved it resets to it, refreshes and updates the plugin,
  recompiles the storefront, clears the cache and then asks the public URL for a 200. A failed
  rebuild or a site that does not come back resets to the commit that was serving before, rebuilds
  from it and sends one mail. Silent otherwise, which is almost every run.
- **It pulls rather than being pushed to, which departs from [TODO.md](TODO.md) deliberately.** That
  file settled on a push-based GitHub Action on 2026-09-03 and asked not to re-open the comparison.
  The reason here differs in kind rather than in cost: a push out of `chimodiazz/website` would put
  an SSH key to this host into a repository whose collaborators and permissions somebody else
  administers. Pulling keeps the credential here, keeps it read-only and opens nothing inbound. The
  decision for this repository is untouched, and item 1 of TODO.md stands.
- **What gets deployed is whatever branch `chimodiazz-src/` is checked out on**, so switching it is a
  `git switch` in that directory rather than an edit to the script. A detached checkout, a branch
  that vanished upstream and a failing fetch each send their own mail rather than going quiet, and
  the fetch failure names the deploy key, because that key lives on a repository this host does not
  own and can be revoked without anything here noticing.
- Fifteen tests in `tests/chimodiazz-deploy.bats`, covering both rollback paths and the three ways
  the remote can be unusable. The `git` stub grew `rev-parse`, `fetch` and `reset`; the `docker` stub
  grew the four console commands. `plugin:update` failing is asserted *not* to be a deployment
  failure, because it exits non-zero when there is nothing to update, which is the ordinary case.

## [1.43.0] - 2026-09-15

### Security

- **dockware's bundled tools were public on sdwa5.org, and are not any more.** Measured 2026-09-15:
  `/adminer/` returned a database login form, `/logs/` the PimpMyLog viewer, and `/mailcatcher` the
  MailCatcher inbox holding every mail the shop had sent, password-reset links included. All three
  answered 200 to anyone, and had since the instance went up. The cause is the image, which wires
  them into the same Apache vhost as the shop and prints them in its own startup banner, so nothing
  in this repository ever pointed at them. The `block_dockware_tools` Caddy snippet answers those
  paths with 404 for every dockware site here. It is a snippet rather than a copied block because the
  second instance runs the same image and would otherwise have repeated the exposure the hour it went
  up. The tools still listen inside both containers, so the firewall and key-only SSH remain what
  stops loopback access.
- **The new instance ran with dockware's published default administrator password for as long as it
  took to rotate it, and never on the public name.** Measured before and after: the default pair
  returned a valid API token, then 400. The `sdwa5.org` instance was checked with the same request
  and already rejected it.
- **The new instance started in `dev` with `debug=true`, and went public in `prod`.** dockware's
  default. The `sdwa5.org` instance was checked rather than assumed: its `.env` carries `APP_ENV`
  twice, `prod` on line 3 and `dev` on line 41, and `bin/console about` reports `prod` with debug
  false, because Symfony's Dotenv does not override a variable it has already set. So the duplicate
  is untidy and harmless there.

### Added

- **chimodiazz.sdwa5.org serves Shopware.** The container was started, the theme from
  `chimodiazz/website` installed, activated and compiled, and the Caddy block swapped from the
  placeholder to `https://127.0.0.1:8444`. The placeholder file is kept as the maintenance page.
- `monitoring/cron.d/chimodiazz-worker` runs the existing `shopware-worker.sh` with
  `SERVICE=chimodiazz_shopware`. Its own lock file, not the shopware one: `flock -n` makes the loser
  exit rather than queue, so a shared lock would let either instance starve the other.
- `chimodiazz_shopware` in `EXPECTED_CONTAINERS`. It is profile-gated but permanently running, so a
  missing one is a fault rather than an expected absence.

### Changed

- **The two Shopware site blocks route through `handle` rather than a bare `reverse_proxy`.** Needed
  for the 404 rule above to take precedence in written order instead of by Caddy's default directive
  order.

## [1.42.0] - 2026-09-15

### Added

- **`chimodiazz.sdwa5.org` answers, which it did not before.** The A record already pointed at this
  host, but Caddy had no site block for the name and therefore no certificate, so every HTTPS request
  died in the handshake with `tlsv1 alert internal error`. The block issues the certificate and
  serves a static placeholder off `chimodiazz-placeholder/index.html`. It is the first and only
  `file_server` block here; every other site is a `reverse_proxy` to a loopback port.
- **A `chimodiazz_shopware` service, defined and deliberately not started.** One
  `dockware/shopware:6.7.11.1` container on `127.0.0.1:8005` and `:8444`, the same exact pin as the
  `sdwa5.org` instance so both stay one shape and a Shopware upgrade is one decision rather than two.
  It is gated behind `profiles: ["chimodiazz"]` because an ungated `up -d` would put an empty shop
  with dockware's published default credentials on a public subdomain.
- **A second outbound deploy key, for `chimodiazz/website`.** GitHub refuses one deploy key on two
  repositories, so the `SdWa5/vps` key could not be reused and an account key is what
  `docs/ssh-hardening.md` exists to argue against. It is read-only, was generated on the host and has
  never crossed the network, and it is reached through its own `github-chimodiazz` alias rather than
  a second `IdentityFile` under `Host github.com`, because ssh offers listed keys in order and GitHub
  answers as whichever repository the first accepted key belongs to. Verified in one session on
  2026-09-15: both aliases greet their own repository.
- `chimodiazz=https://chimodiazz.sdwa5.org/` in the built-in `HEALTH_URLS` default, bumped in the
  script rather than overridden in `.env`, because an override has to repeat every existing entry and
  silently stops watching the ones it forgets. Two tests pin the list so a dropped entry fails there.
- [`docs/chimodiazz.md`](docs/chimodiazz.md), with the measured starting state, the deploy-key
  verification and the numbered steps that bring the container up.
- **A seeding step that the `sdwa5.org` instance never needed, because its directories were filled
  once and the trap stayed invisible.** Measured 2026-09-15 against the image this host already
  holds: `/var/www/html` contains only `shopware.tar.zst`, which `/entrypoint.sh` unpacks solely
  `if [ -f ]`, and `/var/lib/mysql` ships populated. Docker does not seed a bind mount from the
  image, so two empty directories would have produced an empty web root and no database, with no
  error naming the cause. `docs/chimodiazz.md` carries the `docker create` plus `docker cp` recipe.

### Changed

- **`docs/caddy.md` now embeds the Caddyfile byte for byte** instead of a hand-trimmed copy without
  its comments. The doc has always duplicated the whole file, and a copy that drops half the reasoning
  is a copy that drifts.
- **The Shopware image pin keeps its exactness and loses its wrong reason.** The comment said
  dockware publishes no 6.7 series tag. Measured 2026-09-15: `dockware/shopware:6.7-latest` answers
  200, so it does. The pin stays exact because that tag rolls across minor versions and a Shopware
  minor runs forward-only migrations, which is the reason Dolibarr is pinned exactly too.

### Known gaps

- **Nothing notices if the new deploy key dies.** `git_remote` watches the `SdWa5/vps` key only, which
  is the exact trap that check was built for in 1.41.0.
- `EXPECTED_CONTAINERS` does not list `chimodiazz_shopware`, on purpose while it is profile-gated.
  It has to be added in the same sitting the container is first started, together with a
  `chimodiazz-worker` cron entry, or its scheduled tasks stop silently the way the `sdwa5.org`
  instance's did for 47 days.

## [1.41.0] - 2026-09-15

### Added

- **A tenth health check asks whether the checkout can still reach its remote.** `git_remote` runs
  `git ls-remote` against `/opt/docker`'s origin and warns when it fails. It is the check that would
  have caught the deploy-key breakage of 1.40.0, which ran unnoticed for three republish cycles
  because none of the nine existing checks asked. One call covers a destroyed or revoked key, a moved
  remote and a host that cannot reach the forge.
- **The cadence is asymmetric, and that is the substance rather than a detail.** A success is stamped
  and the remote is not asked again for `GIT_REMOTE_MAX_AGE_HOURS` (26), because the call is an
  authenticated round trip watching a fact that holds for months, and hourly would be 24 calls a day
  for nothing. A failure is **not** stamped, so while it is broken the call repeats every run and a
  recovery shows up within the hour instead of a day later. Six tests cover exactly that asymmetry,
  counting the calls rather than reading the status.
- `GIT_CHECKOUT_DIR` names the checkout and defaults to the compose root, because the two are the same
  directory only by convention. `.env.example` and `docs/monitoring.md` carry all three new settings.

### Changed

- **A missing `git` or a directory that is not a checkout warns rather than passing.** A checker that
  cannot see its subject says so, which is the line the firewall check already holds.
- `TODO.md` loses the item this closes.

## [1.40.0] - 2026-09-15

### Security

- **The two superseded private keys are off the host.** `/root/.ssh/id_ed25519`, the old
  account-level key that carried write access to every repository its account could see, and the
  deploy key that the 2026-09-15 republish cycle killed. Deleted only after checking that neither
  fingerprint appeared on the account or on any repository, that neither was in an `authorized_keys`,
  that no cron job or script on the host invokes `ssh`, and that `known_hosts` has only ever held
  `github.com`.
- **`docs/ssh-hardening.md` describes the key that is actually in use.** It still named a key and a
  fingerprint from 2026-09-08 and a deploy key on a personal repository that was deleted on
  2026-09-12. The host had already rotated on 2026-09-13 and rotated again today.

### Fixed

- **A deploy key belongs to the repository object, and recreating the repository destroys it.** Each
  redaction pass republished by renaming the repository, creating an empty one under the old name and
  deleting the rename. The deploy key travels with the renamed repository and dies with it, so after
  each pass `/opt/docker` could no longer pull. Nothing looked broken, because a dead deploy key still
  authenticates and greets with the name of the repository it died with. Measured today: `ssh -T`
  answered `Hi SdWa5/vps-old!` while `git ls-remote` failed with `Repository not found`.
- **The same public key cannot be re-registered afterwards.** GitHub answers `key is already in use`
  for a key whose repository is gone, although it then hangs on no repository and on no account, so
  each pass needs a freshly generated keypair rather than a re-registration. A third keypair was
  generated on the host, registered read-only, and the checkout was brought onto the rewritten history
  with `fetch` plus `reset --hard`, never a re-clone, so the 6.9 GB of untracked runtime state stayed.
  Verified afterwards: `Hi SdWa5/vps!`, `ls-remote` succeeds, `push --dry-run` is refused, all nine
  health checks green.

### Added

- **`TODO.md` records the monitoring gap this exposed.** Nine checks and not one of them asks whether
  the checkout can still reach its remote.

### Changed

- **The passphrase question is answered rather than asserted.** An unattended puller cannot answer a
  prompt, and the two ways round that both put the thing that unlocks the key on the same disk as the
  key, for the same reader. A passphrase defends a key that travels; this one never leaves the host.

## [1.39.2] - 2026-09-15

### Security

- **The history was rewritten, and this repository carried the most of it.** `minecraft-data/server.properties`
  is gone from every commit, so the two machine-generated secrets it held are no longer published by
  publication. Six people's names are gone from ten commits and two commit messages, the board
  member's from the ERP rollout and five more from the changelog's retelling of the member list, and
  a third party's postal address with them. The authorship trailers went in the same pass.
- **The content is provably untouched.** 147 commits before and after, and the tree at `HEAD` is
  `2f562d25` before and after, so only commit objects changed. The working tree had been corrected in
  1.39.0 and 1.39.1 first, precisely so this invariant could hold while content left the history.
- **Republished rather than force-pushed**, which leaves no pre-rewrite objects in GitHub's cache.
  Verified: every probe term returns zero over every blob and every message, the removed path appears
  in no commit, a pre-rewrite SHA answers `not our ref` against a control fetch that succeeds, and the
  suite is 184 tests green with shellcheck clean.

## [1.39.1] - 2026-09-15

### Changed

- **`.claude/` is gitignored, like it already was in `sdwa5-3d`.** The project settings file exists
  only to switch off the authorship attribution, so committing it would disclose exactly what the
  same day's rewrite removed from every commit message.

## [1.39.0] - 2026-09-15

### Security

- **The ERP address rollout named real people in the repository, and the audit of 2026-09-15 found
  it.** `tools/dolibarr/set-address.sh` pinned three ERP ids to the surnames those ids must carry,
  and the tests carried the same names as fixtures. The guard is worth keeping, because a pinned id
  alone would rewrite whoever sits at that id after a re-import, but a surname is personal data in a
  repository that is going public. The record list now lives in a gitignored
  `tools/dolibarr/address-records.json`, with `address-records.example.json` as the committed shape.
  That is the split `sync-pm.sh` already uses for `pm-spec.json`, and `.gitignore` gives the same
  reason. The tests bring their own list with placeholder names, so they exercise all three record
  shapes unchanged.
- **The changelog and `docs/dolibarr.md` retold the ERP member list by name.** Five further people
  were named, three of them deactivated former members, one an external third party, together with
  that third party's own postal address. None of them holds an office and nothing in
  `docs/going-public.md` ever covered them. All are replaced by roles and record ids.
- **`.gitleaks.toml` scopes the plugin-manifest allowlist to the rule instead of to the path.** A
  bare `paths` entry stops gitleaks reading the file at all, which would blind the scan to a secret
  arriving there later; the file argued that itself and then did it anyway. Measured on 2026-09-15
  with a planted key: without any allowlist the manifest yields eleven findings, with the new
  rule-scoped one it still yields the planted key and loses only the ten digests.
- **The commit allowlist is gone**, because `minecraft-data/server.properties` is being removed from
  the entire history in the same pass. There is nothing left to exempt and no commit hash to keep in
  step with the next rewrite.
- **`pull_request` is no longer a trigger.** A public repository lets anyone open a pull request, and
  this workflow runs `tests/run.sh`, which starts containers with the repository bind-mounted. That
  would be a stranger's code executing on a runner. `sdwa5-3d` already holds the same rule.

### Fixed

- **`minecraft-data/` fell under neither licence clause**, although it is 64 tracked files and holds
  1.5 MB of LuckPerms translations produced by third parties. `README.md` now names it alongside
  `shopware-html-data/` as not ours to license.
- **Six places quoted a commit hash that no longer exists.** `c516d41` was invalidated by the rewrite
  of 2026-09-08 and the text was never updated, so `.gitleaks.toml` said so itself while the other
  five kept the dead reference. All six now describe the commit instead, because every rewrite
  invalidates a hash and this history has had four.

## [1.38.0] - 2026-09-15

### Added

- **`tools/dolibarr/sync-pm.sh`, a write path for the ERP's projects and tasks.** The organisation's
  operational backlog was captured in Google Tasks and had no home. It now lives in the Dolibarr
  Projects module, and the repositories' `TODO.md` files stay technical. The script reads a JSON
  spec and makes the ERP match it: dry-run by default, `--apply` writes, a human starts it, the same
  split `tools/dolibarr/set-address.sh` uses. Measured against the live instance on 2026-09-14, the
  ERP held five projects and **zero** tasks, so nothing existed to collide with.
- **The spec is `tools/dolibarr/pm-spec.json` and is gitignored**, with
  `tools/dolibarr/pm-spec.example.json` as the committed shape. The real backlog names people and
  links private documents, and all three repositories are going public. This is the same reason the
  API key is not in `.env.example`.
- **23 tasks across five projects and two new projects**, Krampustek and BGTek. Applied to the live
  instance on 2026-09-15: seven projects, all open with `usage_task` 1, and 23 tasks. A run against
  that state reports `0 to create, 0 to update, 28 already current`.
- `tests/dolibarr-sync-pm.bats`, 28 cases, including the idempotency claim: a second run over an ERP
  that already matches writes nothing.

### Changed

- **`tests/stubs/curl` answers a Dolibarr `POST` with a fresh id per call** instead of a fixed `2`,
  because `sync-pm.sh` creates a project and then posts tasks against the id it got back. It also
  drops the query string when it looks a fixture up, so one `projects` fixture answers
  `projects?limit=500`, and it answers a GET with no fixture with a 404 object, which is what
  Dolibarr does for an unknown record and an empty collection alike.

### Fixed

- **Six facts about the Dolibarr REST API that the script had to be built around**, read off the
  23.0 source and confirmed against the live instance. Three of them were found by the first apply,
  whose second run reported four records to create and one to update instead of nothing, and all six
  are written up in `docs/dolibarr.md`.
  - `ref: "auto"` is **not** optional on a create, because `Task::create()` writes a null ref for an
    empty value.
  - **`GET /projects/{id}/tasks` hides the tasks of a project the API user is not a contact on**,
    even for an admin key, and a project created over this API has no contacts, because the contact
    endpoint exposes `DELETE` and no `POST`. Measured: project 6 held one task, the global list saw
    it, the per-project endpoint returned `[]`, and neither validating the project nor switching
    `usage_task` on changed that. The script reads the global task list and filters by `fk_project`.
    Assigning a project leader stays a UI step.
  - **A project created over the API is a draft with `usage_task` 0**, where every project made in
    the UI is open with tasks enabled. The script sets `usage_task` on create and validates, which
    needs `{"notrigger": 0}` or answers 400.
  - A list endpoint answers an empty collection with a 404 object rather than with an empty array.
  - Numbers come back as strings and an unset number comes back as `null`, so a naive comparison
    would rewrite `progress` on every run.
  - **Dolibarr HTML-escapes what it stores**, so `Allen & Heath` reads back as `Allen &amp; Heath`
    and that one task was rewritten on every run until both sides were decoded.

## [1.37.0] - 2026-09-14

### Changed

- **The Vaultwarden update job runs daily instead of Sunday only, because a weekly actor cannot keep
  up with an hourly detector.** 1.37.3 was published on 2026-09-13 at 15:03 UTC and its image reached
  Docker Hub at 14:55 UTC. That week's run had already happened at 01:00 UTC, fourteen hours before
  the image existed, and correctly did nothing. The next attempt would have been 2026-09-20, so the
  server would have sat behind the Bitwarden clients for a week while `vps-health.sh`, which runs
  hourly, mailed about it on the backoff schedule. Measured on the host: Vaultwarden 1.37.2, image
  `sha256:d5b851ab…` built 2026-08-22, no `docker-compose.override.yml`, all four cron entries
  installed and the health check alive. Nothing was broken. What was missing was a run.
- **`check_vaultwarden_version` now warns on the age of an unapplied release rather than on the
  existence of a new one.** New threshold `VAULTWARDEN_DRIFT_GRACE_HOURS`, default 26, which is the
  update job's period plus two hours of slack, because a release published just after 03:00 waits
  nearly a full day by design. Below the window the check reports `OK` and names the wait; above it
  it warns. **A WARN from this check now means the update job is not working**, which is something
  to act on, where "upstream has shipped" was not. An ordinary upstream release costs no mail at all.
  The release date is read from the same API response as the tag, so there is no second request and
  no way for the two answers to disagree.
- **The stale-health-monitor alarm in `vaultwarden-autoupdate.sh` is rate limited to once a week.**
  It has no backoff of its own, so while the job was weekly a dead `vps-health.sh` cost one mail a
  week and daily would have cost one a day for as long as it lasted. The hold is
  `/var/lib/vps-health/autoupdate-health-alerted`, written only after a mail actually went out, so a
  failed delivery does not silence the next attempt, and removed the moment the health check reports
  in again, so a fault that recurs after a recovery alerts at once. Detection drops from a week to a
  day while the mail cadence stays where it was.

### Fixed

- **A release payload with no `published_at` would have been treated as published today.** GNU
  `date -d ""` resolves an empty string to today at 00:00 and exits 0, so the age check would have
  found every such release comfortably inside the grace window and waved real drift through. The
  emptiness is now tested before `date` sees it. Caught by the test written for it rather than in
  production.

### Added

- Seven tests. Four cover the grace window, including the turn-over at exactly 26 hours driven by
  the clock rather than by two fixtures, the override, and drift whose release date cannot be read.
  Three cover the alarm hold, including that a recovery clears it and that a failed delivery does
  not count as delivered. The `curl` stub gained a `published_at`, defaulting far enough in the past
  that every drift case written before the window existed keeps its meaning. 155 tests, all passing,
  shellcheck clean.

## [1.36.2] - 2026-09-14

### Changed

- **The address rollout is complete and both scripts are now no-ops.** `tools/dolibarr/set-address.sh`
  reports 3 records already current and `tools/shopware/set-address.sh` reports 8, which is the
  idempotence the two were built for. The organisation record in Dolibarr was set in the UI, the one
  step neither script can take because `/setup/company` is `GET` only.
- Two ERP records still hold an Ostermiething address. They are a third party and its contact, and
  that is the third party's own address rather than ours, so both are correctly untouched. Which
  records they are is in the ERP rather than here.

### Fixed

- `TODO.md` item 2.3, the two spellings of one surname, is resolved and deleted. Member 7 and user 4
  now read the same spelling and are linked, `user_id` 4 and `fk_member` 7.

## [1.36.1] - 2026-09-14

### Changed

- **The address change is applied.** Both rollout scripts ran with `--apply` on the live systems.
  Dolibarr: 2 records written and 1 already current. Shopware: all 8 targets written, then
  `cache:pool:clear cache.http` on the VPS. Verified by reading back: `/Impressum/`,
  `/Datenschutz/` and their lowercase twins carry Egitlweg 6 and no longer carry the old address,
  and the three ERP records read back correct.
- **`/Datenschutz/` kept serving the old address after the write while `/datenschutz` did not.** Two
  cache keys for the same page, one hit and one miss. The cache clear resolved it, which is why the
  Shopware script prints that command instead of leaving it implicit.

### Fixed

- `TODO.md` item 2.3 claimed the ERP member list disagreed with the Vereinsregister because a former
  member was still listed. **That was wrong.** Three of the seven members carry `statut=0`, so they
  are deactivated former members and the list is correct. Four members are active. The item is
  removed.
- `TODO.md` item 2.5 asked whether one record should be a member rather than a thirdparty. It is a
  thirdparty on purpose, so the item is removed.
- The remaining name item now names the record that is wrong, user id 4, rather than the spelling
  itself.

### Added

- `docs/dolibarr.md`: **writing a member also updates the linked user.** Measured on 2026-09-14, the
  run wrote `members/2` and then found `users/2` already current, and reading both back confirmed
  the propagation.

## [1.36.0] - 2026-09-14

### Added

- **[`tools/dolibarr/set-address.sh`](tools/dolibarr/set-address.sh)**, which rolls the new postal
  address through the three ERP person records that carry it. Dry-run by default, `--apply` writes,
  idempotent. Record ids are pinned **and** the surname on the record is verified before a write; a
  mismatch aborts, because a pinned id alone would rewrite whoever sits at that id after a merge.
- 13 bats tests in [`tests/dolibarr-set-address.bats`](tests/dolibarr-set-address.bats), including
  the guard above and a test that the organisation record is never written. The shared `curl` stub's
  Dolibarr branch now serves per-path fixtures and logs every request. The suite is 145 tests.
- `docs/dolibarr.md` section **Changing the postal address**.
- `TODO.md` items 2.3 to 2.5, three data-quality findings from reading the ERP.

### Fixed

- **The API client is now verified against the live ERP**, not only against a faked one. 1.34.0
  shipped unverified because the API module was off. `doli.sh status` returns Dolibarr 23.0.2.
- **A successful Dolibarr `PUT` answers with the record id, a bare number.** `has("error")` on a
  number is a jq error, so the first draft of the success check called every successful write a
  failure and aborted after the first record. Caught by the tests before any `--apply` run.

### Notes

- **`/setup/company` exposes `GET` only**, read off the live instance's `explorer/swagger.json` on
  2026-09-14. The organisation's own address is therefore a UI step under Home, Setup,
  Company/Organization, and the script says so instead of pretending to cover it.
- One record needed only its **town** corrected, from `Elsenwang` to `Hof bei Salzburg`. That record
  is where the wrong town entered the documentation in the first place. Elsenwang is a hamlet inside
  the municipality of Hof bei Salzburg and not a postal town.
- Nothing has been written to the ERP yet. The dry run reports 3 records to change.

## [1.35.0] - 2026-09-14

### Added

- **[`tools/shopware/set-address.sh`](tools/shopware/set-address.sh)**, which rolls the
  organisation's postal address through the eight places in the live shop that hold it: the
  Impressum, Datenschutz and AGB CMS slots, `core.basicInformation.address`, and the sender block in
  all four document templates. Dry-run by default, `--apply` writes. Every target is read first and
  skipped when already current, so a second run is a no-op and a half-finished run can be repeated.
- 15 bats tests in [`tests/shopware-set-address.bats`](tests/shopware-set-address.bats) and a
  Shopware branch in the shared `curl` stub that serves canned responses and records every request,
  which is how the dry run is proven to issue no `PATCH`. The suite is now 132 tests.
- `docs/shopware/shop-config.md` section **Changing the postal address**.

### Fixed

- **A successful Shopware write answers 204 with an empty body, and `jq -e` on empty input exits 4.**
  The first draft of the success check therefore called every successful write a failure and aborted
  after the first one. Caught by the test suite before the script ever ran with `--apply`.
- `tests/run.sh` installs `jq` into the bats container alongside `coreutils`. The Alpine image ships
  neither, and both the script and its fixtures build their JSON with `jq`.

### Notes

- **Measured on 2026-09-14: all four document templates still carried Shopware's stock
  `companyName: "Example Company"` with an empty `companyAddress`.** The shop has zero orders and
  zero generated documents, so nothing wrong has been printed, but the first invoice would have
  carried it. The script corrects it in the same pass.
- The place of jurisdiction in the AGB and in the document templates is deliberately untouched. It
  follows the Sitz, and the registered Sitz is still Ostermiething until the Statutenänderung is
  filed and not forbidden.
- Nothing has been written to the shop yet. The dry run reports 8 targets to change.

### Changed

- `README.md` pointed the reader at `github.com/bestcodename/sdwa5` for the org-level documentation.
  That repository was **deleted on 2026-09-12** during the move into the SdWa5 organization, so the
  link was dead. It now points at `github.com/SdWa5/docs`.

## [1.34.1] - 2026-09-14

### Changed

- **The shop identity carries the new postal address.** `docs/shopware/shop-config.md` now reads
  Egitlweg 6, 5322 Hof bei Salzburg, Österreich, which replaced Mühlenstraße 24, 5121 Ostermiething
  on 2026-09-14 by resolution of the Vorstand.
- The same section now says where the storefront legal pages actually live, which is the Shopware
  database rather than this repository, and why the AGB still name Ostermiething as the place of
  jurisdiction. Only the postal address changed. The registered Sitz is still Ostermiething until
  the Statutenänderung is filed and not forbidden, so the jurisdiction clause is correct as it
  stands and changes later, not now.

## [1.34.0] - 2026-09-14

### Added

- **A read-only client for the Dolibarr REST API**, [`tools/dolibarr/doli.sh`](tools/dolibarr/doli.sh),
  with `status`, `company` and a `get` passthrough. The API key is handed to curl through a config
  file on stdin, the same way `send_mail` in `monitoring/lib.sh` passes the SMTP password, so it
  never enters the process list. A test proves that: the fake key appears in the captured config and
  not in the captured argument list.
- 13 bats tests in [`tests/doli.bats`](tests/doli.bats), a Dolibarr branch in the shared `curl` stub,
  and `doli_setup`/`doli` helpers in `tests/test_helper.bash`. `tools/dolibarr/doli.sh` is now in the
  shellcheck list in `tests/run.sh`. The whole suite is 117 tests and passes.
- `docs/dolibarr.md` section **API access**: the one-time setup in the Dolibarr UI, why the key is
  not in `.env.example`, and the three read commands.
- `TODO.md` item 2.1 and 2.2, recording that the Dolibarr read path now exists and that a write path
  is deliberately absent. New item 6.4: **`dolibarr_db` has no consistent dump in cron**, only the
  hot files restic copies, while Vaultwarden has had one since the monitoring work.

### Fixed

- **A disabled API module answers HTTP 200, so a status-code check calls it healthy.** Measured on
  2026-09-14: `https://erp.sdwa5.org/api/index.php/status` returns 200 with the HTML sentence
  `Module <b>Api</b> must be enabled.` `doli.sh` inspects the body for it and reports the module as
  disabled with the path to switch it on, rather than handing a caller HTML it will try to parse.

### Notes

- The API module is **not yet enabled** on the live instance, so the client is unverified against the
  real ERP. It is verified against a faked API only. Enabling the module and creating the dedicated
  API user are UI steps.

## [1.33.0] - 2026-09-13

### Fixed

- **"Key is already in use" is diagnosed, and 1.32.2 recorded it wrongly.** That entry said the key was
  registered "somewhere neither we nor the API can see" and that only Support could locate it. It is
  attached to the **soft-deleted** repository. Four observations fit one explanation: on 2026-09-13 the
  key still authenticated and GitHub greeted it `Hi bestcodename/sdwa5-vps!`, which is the greeting for
  a deploy key rather than an account key; that repository answers 404; the key is on none of the seven
  repositories this account can admin and on no account key; and GitHub refuses it everywhere. A
  deleted repository is restorable for 90 days, so its record and its deploy keys outlive the delete
  while the REST API already reports 404. The registration lapses around 2026-12-11 on its own.
- **The key is not a security problem**, and 1.32.2's closing line overstated it. It is read-only, on a
  repository that serves nothing, and its only private half was removed from the host the same day.

### Added

- `TODO.md` item 7.6: **six deleted repositories are still restorable, so the pre-rewrite history is
  unreachable rather than destroyed.** The three personal repositories deleted 2026-09-12 and the three
  `-old` organization repositories deleted 2026-09-13 can all be restored until roughly 2026-12-11,
  with the private email address in 74 commits and the board members' names in theirs.

  Fetching a pre-rewrite SHA from each new repository returns `not our ref`, with a control fetch
  proving the test works, which establishes that the live repositories do not serve those objects. That
  is the risk that mattered and it is closed. It is **not** proof of destruction, and "cache cleared"
  was written as though it were. Restoring needs owner or organization-admin credentials, so there is
  no route to it from outside and it blocks no publication decision. What it changes is the accuracy of
  the claim.

## [1.32.2] - 2026-09-13

### Removed

- **The dead `id_ed25519_deploy` keypair is off the VPS.** It served the personal repository that was
  deleted on 2026-09-12 and was replaced by `id_ed25519_sdwa5vps` in 1.32.1. Checked before removing:
  nothing referenced it outside a same-day backup of `/root/.ssh/config`, and its public half was not
  in `authorized_keys`, so it granted no inbound access either. `git pull --ff-only` still succeeds.

### Changed

- `TODO.md` item 7.5 keeps the part that is **not** solved by deleting the file. GitHub still refuses
  that public key everywhere with "key is already in use" although it appears on no repository in the
  organization and on no account key, so it is registered somewhere neither we nor the API can see.
  Removing the host's copy does not revoke it, and only Support can.

## [1.32.1] - 2026-09-13

### Fixed

- **`/opt/docker` on the VPS can pull again.** It had been unable to since the 2026-09-12 move, with
  `origin` still naming the deleted personal repository and `HEAD` on a pre-rewrite commit that
  existed nowhere. Nothing noticed, because deploys are manual. It now tracks `SdWa5/vps` at 1.32.0
  and `git pull --ff-only` succeeds unattended. All six containers stayed up, because the change
  touched only documentation and no compose file, monitoring script or hardening config.
- **The organization disallowed deploy keys**, which is GitHub's default for a new organization and
  has no equivalent on a personal repository, so it only surfaced after the move.
  `deploy_keys_enabled_for_repositories` is now `true` on `SdWa5`. That is an organization-wide
  loosening, taken deliberately: the alternative is a personal access token in a file on a
  public-facing host, where a deploy key is read-only and reaches one repository.
- **The host's deploy key is rotated.** Deleting the personal repository took the old key with it, and
  GitHub then refused that public key everywhere with "key is already in use" although it appears on
  no repository and no account visible to us. A fresh `id_ed25519_sdwa5vps` was generated on the host,
  registered read-only, and `/root/.ssh/config` repointed. The dead pair is still on the host and is
  referenced by nothing; `TODO.md` item 7.5 leaves its removal to a human.

### Changed

- `TODO.md` item 7.5 records the repair, and keeps the part that matters next time: a history rewrite
  breaks this again, the fix is `fetch` plus `reset --hard` and never a re-clone, and the deletions
  want checking first because a tracked file that has since become untracked is removed by the reset
  whatever `.gitignore` says afterwards.

## [1.32.0] - 2026-09-13

From the 2026-09-13 audit of all three repositories. The root repository's
`docs/going-public.md` certified items as closed that were not, and two of them landed here.

### Security

- **The Vaultwarden pairing that `sdwa5/docs/services.md` removed was restated in this repository's
  `TODO.md`, with more detail than the table had ever held**, namely which account is on the weaker
  KDF, how much it holds and when it was last seen. Item 7.2 now says only that one of the three
  PBKDF2 accounts is in use, and says why the figures are deliberately absent. Item 7.3 loses the
  cipher, collection and grantee counts and the `SELECT` that reads them, and refers to the new member
  by role.
- **`docs/shopware/privacy-tos-review-2026-07-22.md` is removed from the tree and from the history.**
  It is a dated, itemised list of consumer-protection and data-protection gaps on a live Austrian
  webshop, written by its own operator, and it was in 99 of this repository's 119 commits. Untracking
  it alone would have achieved nothing. The document moves to Google Drive and
  `docs/shopware/TODO.md` item 14 still tracks applying it, without restating what it found.
- `.env.example` loses the one-liner that read the live SMTP password out of
  `/opt/docker/vaultwarden-data/config.json`. The instruction to take the value from Vaultwarden
  stays; the path and the command that prints it do not.

### Fixed

- **`docs/infrastructure.md` and `docs/ollama.md` said the host had no firewall and that an
  unauthenticated Ollama was reachable on `11434`. Neither has been true since 1.11.0.** Measured on
  the live host on 2026-09-13: `iptables -P INPUT DROP` and `ip6tables -P INPUT DROP` with only `22`,
  `80` and `443` accepted, fail2ban's jump at the head of `INPUT`, `DOCKER-USER` ending in
  `-i eth0 -j DROP` with only `25565` excepted, and nothing listening on `11434` or `25565` at all.
  Published unchanged, both files would have advertised an opening that the repository had already
  closed. Rebinding Ollama to `127.0.0.1` is still worth doing and is noted in both files.
- `docs/infrastructure.md`'s directory tree listed `minecraft-data/server.properties` as tracked. It
  has not been since 1.25.0, which is the whole point of `server.properties.example`.
- `TODO.md` item 5.3 said four Minecraft usernames. There are **five** distinct ones, counted
  2026-09-13, several appearing twice with an offline and an online UUID. The disclosure decision is
  unchanged; the count was simply wrong.

### Added

- `TODO.md` item 7.5: **`/opt/docker` on the VPS still points at the deleted personal repository** and
  has been unable to pull since the 2026-09-12 move, which nothing noticed because deploys are manual.
  Measured 2026-09-13.

## [1.31.1] - 2026-09-12

### Security

- **The two Obmann-Stellvertreter are out of the history, not just out of the tree.** 117 commits
  rewritten, tree hash unchanged at `e49d1314`, commit count 117 before and after, and zero commits
  left holding either name. They were in 95 of the 117, in
  `docs/shopware/privacy-tos-review-2026-07-22.md`.
- **`Mühlenstraße 24` is kept in all 117 on purpose.** <https://sdwa5.org/Impressum> publishes it
  today and an Austrian webshop must state a Zustellanschrift by law, so removing it from git while
  the shop states it would achieve nothing. What went with the names is the `c/o <name>` prefix, so
  the history no longer says whose home it is.
- **`.gitleaks.toml`'s allowlisted commit `9f800d7` did not move**, checked rather than assumed, so
  the history scan is unaffected. It sits earlier than any line this rewrite touched, and a commit
  only moves when it or an ancestor changes.

## [1.31.0] - 2026-09-12

### Added

- **A licence.** MIT in `LICENSE` for `monitoring/`, `hardening/`, `minecraft/`, `tests/`, `.github/`,
  `Caddyfile`, `docker-compose*.yml` and `.env.example`. CC BY-SA 4.0 in `LICENSE-docs` for `docs/`,
  `README.md`, `CHANGELOG.md` and `TODO.md`. **`shopware-html-data/` is carved out and stated as
  such**, being store-installed Shopware plugin content that is tracked only because those plugins are
  not managed through composer, so each carries its own vendor's terms rather than ours.

### Changed

- **The two Obmann-Stellvertreter defer to the ZVR register in
  `docs/shopware/privacy-tos-review-2026-07-22.md`.** That file drafted Impressum text naming all three
  board members, and the live Impressum at <https://sdwa5.org/Impressum> names only the Obmann, which
  is all Austrian law requires. So the draft would have published two names that nothing else does.
  The file itself left the repository and its history in 1.32.0.
- **The `c/o <name>` prefix is gone from the postal address and the Zustellanschrift**, in both the
  inline and the `<br>`-separated form. The address itself stays, because the Impressum publishes it
  by law and removing it from git while the shop states it would achieve nothing.

### Measured, and worth stating plainly

- **The tree is clean and the history is not.** Both names remain in 95 of the 115 commits, in that
  same file. A rewrite is prepared and was refused by the environment's `[Git Destructive]` guard, so
  it is outstanding, and it is the last item that cannot be done once this repository is public. See
  `SdWa5/docs`'s `docs/going-public.md`.

## [1.30.0] - 2026-09-12

### Security

- **The private email address is gone from the history, not just from the working tree.** 1.24.0 took
  it out of all five files and said "this removes the address from the working tree and not from the
  history. One commit's content carried it". The first half was right and the count was wrong.
  Measured on 2026-09-12: **74 of the 113 commits** carried it, in `README.md`, `monitoring/lib.sh`,
  `.env.example`, `docs/monitoring.md` and `docs/infrastructure.md` at once, from the first commit on
  the branch through 1.5.0.
- **The 2026-09-08 rewrite could not have fixed this and was never meant to.** That one replaced the
  author and committer fields of every commit, which is a different thing from what a file says.
  `gitleaks` does not catch it either, in tree or in history, because an email address is not a
  credential. So it was invisible to both of the measures already in place.
- **The address was removed together with its separator rather than substituted.** On every one of the
  six line shapes it ever had it stood next to `ripper@sdwa5.org` as the second recipient, so
  substituting would have left `ripper@sdwa5.org ripper@sdwa5.org` in the recipient lists and "mail X
  and X" in the prose, in all 74 commits. `monitoring/lib.sh` now reads
  `MONITOR_MAIL_TO="${MONITOR_MAIL_TO:-ripper@sdwa5.org}"` throughout the history, which is character
  for character what 1.24.0 wrote by hand.
- **The content is provably untouched.** `HEAD`'s tree hash is `c887c21519b3e13ab714735ad46a144abfb1d4f7`
  before and after, which it must be, since the working tree was already clean. The commit count is
  113 before and after, zero commits reachable from `origin/main` contain the address, and a grep for
  a doubled recipient across all five files in all commits finds none.
- **`.gitleaks.toml`'s commit allowlist survived this rewrite untouched**, and that was checked rather
  than assumed. `9f800d7` is the second commit on the branch, earlier than the first appearance of the
  address, so it and all its ancestors kept their hashes. The 2026-09-08 rewrite did move it, which is
  why the file carries a warning about it.

### Changed

- `.gitleaks.toml` records that the 2026-09-12 rewrite left the allowlisted commit in place, and why,
  so the next person rewriting history knows the check is "is `9f800d7` still reachable" rather than
  "update the line".

## [1.29.2] - 2026-09-11

### Changed

- **Every job states a `timeout-minutes`, and the workflow states a `concurrency` group.** GitHub's default
  timeout is 360 minutes, and that default is what let `sdwa5-3d`'s `full` job burn roughly 1644 minutes across
  three nightly runs in September before anybody saw a log, because a job cancelled at the ceiling reports only
  that it was cancelled. The concurrency group cancels a superseded push. It is deliberately **not** applied on
  `main`, because a merge commit's green run is what a release is judged by.
  Nothing here is expensive — this repository's runs are about a minute — so the change is about the rule being the same
  in all three SdWa5 repositories rather than about the minutes.


## [1.29.1] - 2026-09-09

### Fixed

- **The `.gitleaks.toml` allowlist pointed at a commit SHA that the history rewrite changed**, so the
  two Minecraft secrets in `minecraft-data/server.properties` became findings again and the history
  scan went from clean to failing. Updated to the rewritten SHA, `9f800d7`.
- The comment now says plainly that **a commit SHA is not immutable and this one has already moved
  once**, that anything rewriting history has to update the line, and how to find the commit again
  with `git log --diff-filter=A -- minecraft-data/server.properties`. The ten Shopware plugin
  checksum findings were unaffected, because those are allowlisted by path.

## [1.29.0] - 2026-09-08

### Security

- **`sdwa5-firewall.sh` re-adds fail2ban's jump itself, because fail2ban does not.** Flushing `INPUT`
  removes the jump fail2ban puts at its head, and the unit's `ExecStartPost` restarted fail2ban so
  fail2ban would re-insert it. **Measured 2026-09-08, that does not work.** After
  `systemctl restart sdwa5-firewall`, fail2ban restarted and logged `Server ready` and
  `Creating new jail 'sshd'`, and thirty seconds later the jump was still absent. The same commands
  run by hand insert it without complaint, so the cause inside fail2ban 1.0.2 is not established,
  only the effect is. The effect is that **every firewall restart and every boot silently switched
  off SSH brute-force filtering** while `iptables -S INPUT` still looked plausible.
- It was found because the new `DOCKER-USER` check fired on its own first deployment, which is the
  check doing exactly what it was written for.
- The jump is only re-added when the `f2b-sshd` chain exists, because creating that chain is
  fail2ban's job and a jump to a missing chain fails.
- **The `ExecStartPost` restarting fail2ban is removed, which buys a second thing.** A fail2ban
  restart logs `Flush ticket(s) with iptables-multiport` and discards every active ban, so the old
  arrangement threw away the bans it was trying to protect. Bans now survive a firewall restart,
  because nothing touches the `f2b-sshd` chain.

### Added

- `tests/sdwa5-firewall.bats`, the first tests this script has had, taking the suite from 91 to 104.
  They cover the `INPUT` rebuild, the service ports, bridge discovery, every `DOCKER-USER` rule
  including that egress is `RETURN` and never `ACCEPT`, the external interface coming from the default
  route, and three cases for the fail2ban jump: re-added when its chain exists, left alone when it does
  not, and not inserted twice.
- A `tests/stubs/ip` stub, and the `iptables` and `ip6tables` stubs now log every invocation so a test
  can assert what a script tried to write. `STUB_IPT_HAVE` matches one pattern per line rather than per
  word, because both `-C` checks in this script mention `f2b-sshd` and word splitting made either
  satisfy both.
- `docs/ssh-hardening.md` records that **`fail2ban-client stop <jail>` is not reversible with
  `start <jail>`**. `stop` removes the jail from the running server and `start` then fails with
  `UnknownJailException`, leaving the jail not running at all. Learned while diagnosing this, and it
  briefly left the sshd jail down.

## [1.28.0] - 2026-09-08

### Security

- **`sdwa5-firewall.sh` now owns `DOCKER-USER` alongside `INPUT`, so a published container port is
  filtered at all.** Until now the firewall owned `INPUT` alone, and a published port is DNAT'd in
  `nat/PREROUTING` and traverses `FORWARD`, so the `INPUT DROP` policy never saw it. `DOCKER-USER` was
  Docker's empty `-j RETURN`. The chain now returns established traffic and container egress, returns
  tcp and udp 25565 because `minecraft` publishes on all interfaces on purpose, and drops everything
  else arriving on the default-route interface.
- **Every allow is a `RETURN` and never an `ACCEPT`.** `RETURN` hands the packet back to `FORWARD` so
  Docker's `DOCKER-ISOLATION` and `DOCKER` chains still judge it, while `ACCEPT` would skip them and
  quietly switch off Docker's isolation between compose projects, which is a bigger hole than the one
  being closed.
- The external interface is derived from the default route rather than hardcoded, measured as `eth0`,
  and the chain is created if absent so a boot before Docker cannot make the script fail.
- **The `firewall` check now CRITs when `DOCKER-USER` is missing or back to a bare `-j RETURN`.**
  Anything that flushes the chain, including a Docker restart, would otherwise leave every published
  port unfiltered while the chain still looks present, which is precisely how this went unnoticed.

### Added

- Three tests, taking the suite from 88 to 91. The `iptables` stub now dumps per chain, so a test can
  express an empty `DOCKER-USER`, a missing one, or a filtering one.
- `docs/ssh-hardening.md` replaces the section that asserted the firewall "does not filter published
  container ports, and cannot" with what it now does, including the rule order, the reason every allow
  is a `RETURN`, and the updated coverage table.

### Changed

- **There is no IPv6 counterpart, and that is measured rather than skipped.** Docker does no IPv6
  publishing on this host: `ip6tables` holds zero Docker rules, the v6 `nat` table holds zero DNAT
  entries, both bridges carry only a link-local `fe80::` address, and there is no
  `/etc/docker/daemon.json` at all. So there is no v6 path to a container to filter. Enabling Docker's
  IPv6 changes that, and a v6 counterpart then needs `nft`, because `ip6tables` reports the v6
  `DOCKER-USER` chain as incompatible with its compat layer.

### Removed

- `TODO.md` item 7.4, done here.

### Deployment

- `hardening/firewall/sdwa5-firewall.sh` has to be copied to `/usr/local/sbin/` and the unit
  restarted. The rollback for a mistake is `iptables -F DOCKER-USER; iptables -A DOCKER-USER -j RETURN`,
  which restores Docker's default. SSH cannot be affected, because it lives in `INPUT`.

## [1.27.1] - 2026-09-08

### Fixed

- **The `shopware_tasks` check reported "No Shopware scheduled task has ever run" against a healthy
  task list.** Its `awk` matched the year as `{4}`, and **the host's `awk` is `mawk`, which does not
  honour interval expressions**. Measured on the host: `/^[0-9]{4}-/` matches nothing while
  `/^[0-9][0-9][0-9][0-9]-/` matches. Now written with literal digit classes.
- **The test suite could not have caught this**, and that is recorded in `docs/monitoring.md` rather
  than left as a surprise. `tests/run.sh` runs bats in an Alpine container whose busybox `awk` does
  support intervals, and the workstation has GNU awk 5.2.1, so three implementations are in play and
  only the host's decides. Anything parsed with `awk` in this repository stays inside POSIX from here.
  It was found by running the check on the host after deploying rather than by trusting the green
  suite.

### Added

- `docs/monitoring.md` records the catch-up behaviour of Shopware's scheduler, because it looks like a
  defect and is not. After the 47-day outage each task needed **two** runs to get back onto its
  schedule: Shopware clamps a task's next execution to *now* when the computed next time is still in
  the past, so the first run leaves it immediately due again. Measured across three consecutive worker
  runs, after which `shopware.invalidate_cache` sat at +300s, `log_entry.cleanup` at the next day and
  `app.system_heartbeat` at the next week, and a further run changed nothing.

## [1.27.0] - 2026-09-08

### Added

- **`monitoring/shopware-worker.sh` runs Shopware's scheduled tasks and consumes its message queue.**
  Nothing had, since 2026-07-23, so every task's next execution was 47 days in the past, cache
  invalidation was dead on a 300-second interval, every cleanup task was dead, the sitemap's `lastmod`
  was frozen at 2026-07-22 and 9 messages sat unconsumed. It runs every minute from
  `/etc/cron.d/shopware-worker`, silent on success and one mail on failure.
- Three details in it are deliberate. **`flock -n` is not decoration**, because Shopware's own
  documentation warns that cron-driven workers pile up: cron does not wait for the previous run and a
  message outliving the time limit keeps its worker alive. **The `failed` transport is consumed too**,
  because without it a failed message is never retried. And **the tasks run before the consumer**, so a
  message a task enqueues is picked up in the same minute rather than the next.
- `shopware-html-data/config/packages/shopware.yaml` turns the admin worker off, which Shopware
  requires once a CLI worker exists so the two do not both run.
- **The `shopware_tasks` check in `monitoring/vps-health.sh`, which matters more than the fix.** This
  outage went unnoticed for 47 days because nothing watched it. The check reads
  `scheduled-task:list` itself rather than any symptom, and takes the **newest** last-execution across
  all tasks, because the intervals run from 60 seconds to a month so a single old task proves nothing.
  CRIT past `SHOPWARE_TASK_MAX_AGE_HOURS`, default 2.
- 15 tests, taking the suite from 73 to 88. `tests/shopware-worker.bats` covers a healthy run, both
  command failures, a stopped container, the transport list and the ordering of the two steps.
  `tests/vps-health.bats` gains a 48-hour outage, a list where only the newest task is recent, an
  unreadable list, a list where nothing has ever run, and a fixture whose timestamp is UTC while the
  test runs in the host's zone, which is the same trap the backup check fell into.

### Fixed

- `README.md` and `docs/monitoring.md` said "three cron jobs". There are four.

### Security

- **Five Shopware AG service apps are installed and four are active**, namely `ShopwarePayments`,
  `Swag3DModelPipeline`, `SwagAIImageEditor` and `SwagCopilot`, with `ShopwareNexusIngestionService`
  present but inactive. Found while draining the queue by hand: consuming one message showed
  `UpdateServiceMessage` calling `registry.services.shopware.io` and updating `ShopwarePayments`. They
  install and update themselves through the `services.install` task. None appears in
  `docs/shopware/privacy-tos-review-2026-07-22.md`, so whether a non-profit wants an AI image editor, a
  Copilot and an event ingestion service active on its shop is now filed as item 1 of
  `docs/shopware/TODO.md` rather than sitting unnoticed.

### Removed

- `docs/shopware/TODO.md` item 1, the missing task runner, done here. Item 8's sitemap half is closed
  too, since the sitemap regenerates again, leaving only the Search Console submission and the meta
  titles.

### Deployment

- `/etc/cron.d/shopware-worker` has to be installed, and `bin/console cache:clear` run once so the
  admin worker setting takes effect. The queue holds 21 messages, mostly thumbnail jobs, and the worker
  drains them a minute at a time.

## [1.26.0] - 2026-09-08

### Security

- **Nothing runs Shopware's scheduled tasks or its message queue, and nothing has since 2026-07-23.**
  Found while measuring the SEO item in `docs/shopware/TODO.md`. There is no host cron entry, no
  container crontab entry beyond Debian's own, no running `scheduled-task:run` or `messenger:consume`,
  and no worker service in `docker-compose.yml`. Every scheduled task's next execution is therefore 47
  days in the past, **`shopware.invalidate_cache` is dead on a 300-second interval**, every cleanup
  task is dead so `log_entry`, `cart`, `payment_token`, `sales_channel_context`, `version` and
  `import_export_file` grow unpruned, and 9 messages sit unconsumed in the `async` transport with 0
  failed. Written up in `docs/shopware/infrastructure.md` and filed as item 1 of
  `docs/shopware/TODO.md` at ca. 1 Stunde 30 Minuten, because the fix needs a decision about where
  that process lives and it touches a live internet-facing shop.
- The likely mechanism is recorded as a **hypothesis rather than a measurement**: all tasks stop at
  the same moment and `shopware.invalidate_cache` shows a last run four minutes before its next due
  time, which is what the admin worker looks like, since it only runs tasks while somebody has the
  administration open. The effective `enable_admin_worker` value could not be read, because
  `bin/console debug:config` fails with "Impossible to call set() on a frozen ParameterBag" in this
  build.

### Fixed

- **`docs/shopware/TODO.md` said "no sitemap submitted". A sitemap exists.** Re-measured: HTTP 200 at
  `https://sdwa5.org/sitemap.xml`, a valid `sitemapindex`, **32 URLs** covering the homepage, 13 CMS
  pages, 5 category listings and 13 products, and `robots.txt` advertises it twice, for the default and
  the `/de/` sales channel. What is actually wrong is its `lastmod` of 2026-07-22, which is the same
  date the sitemap task last ran, so the stale sitemap is a symptom of the item above rather than a
  separate problem. Whether it has ever been submitted to Google Search Console is unknown from here.
- The storefront search item is now measured rather than suspected. `?search=Hoodie` returns products,
  while `Membership`, `Hardware`, `Impressum`, `Datenschutz` and `Gallery` return nothing, although all
  five exist as CMS pages and all five are in the sitemap. So it is product-only as suspected, core has
  no CMS-page search, and whether a free plugin exists is the open question.
- `docs/shopware/infrastructure.md` said the shop is reverse-proxied via nginx. It is **Caddy**.
- `docs/shopware/TODO.md` items are renumbered after the insertion, and the internal reference from the
  preorder item to the legal-wording item was corrected from 13 to 14.

## [1.25.0] - 2026-09-08

### Added

- **The Modrinth mod list moved out of `docker-compose.yml` into
  `minecraft/modrinth-mods.txt`.** `MODRINTH_PROJECTS` now points at it as
  `@/extras/modrinth-mods.txt`, mounted read-only from outside `/data` because it is
  repository-owned configuration rather than server state. The image ignores blank lines and lines
  starting with `#`, which is the whole point: **a disabled mod can be commented out and stay
  visible** instead of having to be deleted, which is what used to happen and left no record it had
  ever been there.
- All 15 entries were extracted from the compose file rather than retyped, and verified identical in
  content and order against the previous commit.
- `docs/minecraft.md` no longer repeats the list, so the two cannot disagree, and it documents the
  line syntax: a bare slug takes the newest matching build, `slug:version` pins one as `dcintegration`
  is held at `3.1.0.1-1.21.3`, and a trailing `?` marks a project optional.

### Removed

- `TODO.md` item 5.1, done here.

### Deployment

- **Unverified against a running server.** The Minecraft profile is down and the image is not present
  on the host, so the `@` listing-file syntax rests on the image's documentation rather than on a
  start here. `docs/minecraft.md` carries the verification recipe for the next deliberate start. If
  the syntax were wrong the server would fail at startup, which is a visible failure rather than a
  silent one.

## [1.24.0] - 2026-09-08

### Security

- **A private, non-organisation email address was hardcoded in `monitoring/lib.sh` as a default alert
  recipient**, and repeated in `README.md`, `.env.example`, `docs/monitoring.md` and a diagram node in
  `docs/infrastructure.md`. Publishing this repository would have published it in all five places. The
  default is now `ripper@sdwa5.org` alone, and the host keeps its own recipient list in
  `/opt/docker/.env`, which is gitignored. The effective recipients on the host are unchanged, still
  two addresses, verified by counting them rather than printing them.
- **This removes the address from the working tree and not from the history.** One commit's content
  carried it, and far more importantly **all 95 commits in this repository are authored and committed
  as that address**, because it is the git identity that made them. No change to a file can alter
  that, so it stays a decision for the owner before the repository goes public.
- `.gitignore` now covers `.env.*` rather than `.env` alone, with `!.env.example` kept. A hand-made
  `.env.bak-*` was untracked but not ignored, so it appeared in `git status` in the deploy checkout,
  which is exactly what the file's own comment says makes "is this host clean?" useless as a deploy
  precondition.

## [1.23.0] - 2026-09-08

### Fixed

- **`hostname: sdwa5-vps` is pinned on the restic service, because the retention policy did not mean
  what it says.** `restic forget` groups by `host,paths` by default and restic records
  `os.Hostname()` on each snapshot, which in a container is the container ID. Every recreation of the
  container therefore started a fresh retention group with its own full allowance of 6 daily, 3
  weekly, 11 monthly and 2 yearly. Measured 2026-09-08: **11 distinct hostnames across 61
  snapshots**, where a single group would hold 17. Adding `init: true` in 1.21.0 created one of those
  groups.

### Added

- `docs/backup.md` gained a Retention groups section with the measurement, including the repository at
  100.889 GiB of raw data across 176 717 blobs, the Drive folder at 106.230 GiB in 22 655 objects, and
  the Shared Drive quota at 100 TiB with 99.870 TiB free.

### Changed

- **The 44 extra snapshots are deliberately kept**, and the reasoning is recorded so it is not
  reopened as an oversight. `--group-by paths` in `RESTIC_FORGET_ARGS` would apply the policy across
  all eleven groups and, with `--prune` already there, delete 44 snapshots on the next run. Storage is
  not a constraint at a tenth of a percent of quota, more history is safer than less for a backup, and
  the only real cost of the extra groups is a longer `prune` walk against a run measured at 47
  seconds. So the fix stops new groups forming rather than collapsing the old ones.

## [1.22.1] - 2026-09-08

### Security

- `docs/ssh-hardening.md` documents the **outbound** key this host uses to reach GitHub. Everything in
  that document was about getting in, while `/opt/docker` is a git checkout that pulls this
  repository, and until 2026-09-08 it did so with an account-level key titled "sdwa5.org Contabo VPS".
  An account key carries the account's whole reach, so root on this VPS had read **and write** access
  to every repository `bestcodename` can see, while the machine needs to pull exactly one. A
  compromise of this host was a compromise of every repository.
- It now pulls with a read-only deploy key scoped to this repository alone, `id=162604148`,
  `read_only: true`, and `/root/.ssh/config` pins it with `IdentitiesOnly yes` so the old key still on
  disk cannot be offered by accident. Verified independently: `git ls-remote` succeeds,
  `git push --dry-run` is refused, and `ssh -T git@github.com` greets as
  `Hi bestcodename/sdwa5-vps!` rather than `Hi bestcodename!`, which is the clearest signal of scope
  because a deploy key identifies as the repository.
- Recorded that pushing from this host now fails by design, that nothing in this repository does, and
  that the deploy automation in `TODO.md` runs the other way round and is unaffected. Also recorded
  why the deploy key has no passphrase, namely that an unattended puller cannot answer a prompt, so
  the mitigation is its scope rather than encryption at rest.

## [1.22.0] - 2026-09-08

### Fixed

- **`check_backup` asked the container log and now asks the repository.** Reading the log produced two
  false alarms, both found on 2026-09-08.
  - A container recreation wipes the log, and an empty log cannot be told apart from a backup that
    never ran. Adding `init: true` to the restic service in 1.21.0 was itself enough to fire
    `CRIT No completed restic backup found in the last 400 log lines` against a repository that was
    entirely healthy. That alarm was real and its subject was not.
  - **The log prints UTC and the host read it as Europe/Berlin.** The restic container has no `TZ`,
    so its `Finished Backup at` lines are UTC, while `date -d` on a bare timestamp uses the host's
    zone. Every backup was therefore computed **two hours older than it was**, measured: a snapshot
    two hours old came out as four. Against a 24-hour cycle and a 26-hour threshold that leaves no
    slack at all, and it placed a false CRIT window at exactly the hour the next run starts. This one
    had never been noticed, because it fires on a healthy backup with nothing visibly wrong.
- `restic snapshots --json` answers both. It is the authoritative answer to whether a backup exists
  rather than a claim in a log that a recreation can erase, and its timestamps are RFC3339 with an
  explicit offset, so the host's zone cannot misread them. The newest snapshot is taken as the maximum
  of the returned timestamps rather than the last element, so the check no longer depends on restic's
  ordering.
- The log is still read, but only as an early warning for an explicitly failed run. It can no longer
  raise an alarm by being absent.
- **`docs/monitoring.md` carried the same wrong schedule arithmetic twice.** It said the database copy
  runs "ten minutes before restic at 04:00" and that the Vaultwarden update runs "one hour before" it.
  Both crons are host time and Europe/Berlin while restic's is container time and UTC, so the real
  gaps are 2 hours 10 minutes and 5 hours. The ordering holds in both cases, so nothing was broken,
  but it held by arithmetic nobody had checked across two timezones.

### Added

- Six tests for the backup check, including two that name the bugs they guard. One feeds a container
  log containing only the four lines a fresh container writes and asserts silence. The other asserts
  the computed age of a snapshot whose timestamp is UTC while the test runs in the host's zone, so a
  check that ignored the offset would read 3h where the fixture says 1h.
- `tests/test_helper.bash` gained `restic_snapshots_json`, which builds a `snapshots --json` array
  from epoch seconds and emits UTC with a `Z` offset exactly as restic does. The fixture is
  deliberately in a foreign timezone, because that is the shape of the bug it replaced.
- The remaining cases cover an unreachable repository, a repository with no snapshots at all, and a
  list returned out of order.

## [1.21.1] - 2026-09-08

### Fixed

- `actions/checkout` bumped from `v4` to `v5`, which GitHub's deprecation notice asks for.
- `.github/workflows/tests.yml` now states plainly that nothing in it has ever executed. Every run in
  all three SdWa5 repositories is refused within seconds on account billing, measured 2026-09-08, so
  the local `tests/run.sh` and `gitleaks` runs are the only evidence this pipeline works. The
  workflows are correct as written and unverified as run, and the distinction is worth having in the
  file rather than only in a changelog.

## [1.21.0] - 2026-09-08

### Added

- **The restore drill has been run, and it passed.** `docs/backup.md` gained a Restore drill section
  with the recipe and what the first run measured. Restoring the vault database from snapshot
  `b672181d` took 6 seconds, `PRAGMA integrity_check` returned `ok`, and the database held 29 tables
  with 4 users, 450 ciphers, 1 organization and 5 collections against a live vault of 455 ciphers,
  which is the expected daily drift. The repository was previously unproven end to end.
- The drill restores through the existing `restic` container on purpose, because it already holds
  `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and the rclone config, so the drill never handles the
  repository password. It also deletes the restored copy afterwards, which is not tidiness: that file
  is every credential the association has.
- `docs/backup.md` records that the Contabo whole-VM backup is deliberately **not** drilled, because
  testing it means replacing the running host, and that it stays worth having as the only copy that
  survives losing the Google account.

### Fixed

- **`docs/backup.md` said the database copy runs "ten minutes before restic". It does not.** The copy
  is host cron and therefore Europe/Berlin at 03:50, so 01:50 UTC, while restic is container cron with
  no `TZ` at 04:00 UTC. The real gap is 2 hours 10 minutes, and 3 hours 10 minutes under CET. The
  ordering is still correct in both, so nothing is broken, but it held by arithmetic nobody had
  checked. The schedule is now stated in UTC in both the document and `docker-compose.yml`.
- **The restic container leaked zombie processes**, 108 of them measured after 51 days up. Its PID 1
  is `tail -fn0 /var/log/cron.log`, which never reaps the `rclone` children each run spawns. Fixed
  with `init: true` on the service.
- The reason for restoring the vault from `vaultwarden-db-backup/db.sqlite3` rather than the hot copy
  is now stated from measurement rather than as a warning. The live database is in WAL mode with a
  552 KB `-wal` beside it, every snapshot captures all three files non-atomically, and **a main file
  restored without its `-wal` opens cleanly and silently presents an earlier state** — the hot copy
  returned `integrity_check ok` in the drill. So `integrity_check` is not evidence that a hot restore
  is complete, which is what makes it dangerous.

### Removed

- `TODO.md` item 6.3, the restore drill, done here.

## [1.20.1] - 2026-09-08

### Fixed

- 1.20.0 said `shopware` and `dolibarr` "will not move", which was true of the image content and
  wrong about the containers. Changing an image *reference* is enough for `docker-compose up -d` to
  recreate a container, and the host's images were tagged `:latest` locally, so the pinned names were
  not present and `up -d` would have pulled and recreated three services for no gain. The running
  images were given their pinned names on the host, which is accurate because that image is
  6.7.11.1, and `up -d` now recreates `dolibarr_db` alone. `mariadb:12.3` was deliberately left
  untagged so its patch upgrade stays a real, deliberate step.
- `docs/maintenance.md` records the check to run before `up -d`, which compares each service's
  running image id against the id its configured tag resolves to.

## [1.20.0] - 2026-09-08

### Changed

- **Every image tag is pinned.** All twelve were on `:latest` and only Vaultwarden was ever pulled, so
  `:latest` delivered neither updates nor reproducibility. The hazard it did carry was a future
  `docker-compose pull` crossing a major version under a live database: measured 2026-09-08,
  `mariadb:latest`, `lts`, `12` and `12.3` all pointed at one digest, so `latest` was 12.3 and would
  have followed to 13 on its own. Each tag was chosen by finding which real Docker Hub tag carries the
  digest that is running, rather than by reading a version number out of the container.
  - `dockware/shopware:6.7.11.1`, exact, since dockware publishes no `6.7` series tag.
  - `dolibarr/dolibarr:23.0.2`, exact, for both `dolibarr` and `dolibarr_cron` and for the two project
    services. A Dolibarr minor upgrade runs forward-only database migrations and no restore drill has
    been done yet, so the `23` tag was rejected because it would let 23.x move on its own.
  - `mariadb:12.3`, minor series rather than exact, in both compose files. Patch updates inside 12.3
    are safe and wanted; the major-version jump is the one-way door.
- Four images keep `:latest`, each with the reason written at the line so nobody pins them later.
  `vaultwarden` is owned by its weekly auto-update script and a pin would freeze security updates for
  a password vault. `restic` has nothing to pin to. `minecraft` and `ollama` are profile-gated and not
  present on the host, and Minecraft's build is decided by its `VERSION` environment variable.

### Added

- `docs/maintenance.md` gained an **Image versions** section: the per-service table with its reasons,
  the warning that pinning is not a no-op on the next pull, and the procedure for bumping a pinned
  service.
- `docs/maintenance.md` now states that `docker-compose.projects.yml` carries its own copy of the
  `x-logging` anchor, since YAML anchors do not cross files, and that both must be kept in step.

### Security

- **The image carrying both backups is five years old.** `lobaro/restic-backup-docker:latest` has not
  been pushed since 2021-05-05, and the newest version tag in the repository is `1.3.1-0.9.6` from
  2020. It cannot be pinned to anything better, so it is now filed as an explicit decision rather than
  sitting unnoticed behind a `:latest` that looks current.

### Removed

- `TODO.md` item 6.1 asked to decide between auto-update, pinned tags with renovate, and a manual
  window. The mechanism is settled and built, so the item is now only about cadence, and renovate
  waits on the repositories going public.
- The stale note in `docs/maintenance.md` saying the project compose file has no logging cap. It has
  one since 1.19.0.

## [1.19.0] - 2026-09-08

### Security

- **`minecraft-data/server.properties` was tracked and held two live secrets**, a 24-character
  `rcon.password` and a 40-character `management-server-secret`, committed with the Minecraft data
  directory and found on 2026-09-08 while checking what going public would publish. Both were rotated on the host and the
  file is no longer tracked. A public repository publishes every past commit at once, so a scrubbed
  `HEAD` would not have helped, and rotation is the fix rather than a history rewrite.
- Neither secret was ever reachable from outside. `rcon.port` is `25575` and is not published to the
  host, so RCON answers only inside the container network, and `management-server-enabled` is `false`
  with `management-server-port` at `0`. This was a publication problem, not an exposure.
- **`rcon.password` was never configuration in the first place.** The image's
  `scripts/start-configuration` generates it with `openssl rand -hex 12` whenever `RCON_PASSWORD` is
  unset, and it is unset in `docker-compose.yml`. The committed value was 24 lowercase hex
  characters, which is exactly that, so it was ephemeral image output that had been committed once
  and then republished on every clone.
- `ollama` published `11434:11434` on all interfaces with no authentication of any kind, and now
  binds `127.0.0.1`. The host firewall could not have covered this: a published port is DNAT'd and
  traverses `FORWARD`, where `DOCKER-USER` is an empty `RETURN`, so the `INPUT DROP` policy never
  sees it. Profile-gated and down, so nothing was open, but it would have been public the moment the
  profile started.

### Added

- Continuous integration, in `.github/workflows/tests.yml`. This repository had no CI. The `tests`
  job runs `tests/run.sh`, which already runs bats and shellcheck inside containers, so CI and a
  local run are the same thing. The `secrets` job scans the working tree and the full history with
  gitleaks.
- `.gitleaks.toml`. It allowlists Shopware plugin `checksum.json` files, whose values are hex digests
  that a high-entropy rule reads as ten secrets, and it allowlists the one commit that was reviewed in
  full and remediated. The commit is allowlisted rather than the path, because a `paths` entry stops
  gitleaks reading the file at all and would blind the working-tree scan to anything arriving there
  later.
- `minecraft-data/server.properties.example` carries every key with the two secrets blanked, so the
  server's actual settings stay documented now that the real file is untracked.
- `docker-compose.projects.yml` gained its own `x-logging` anchor and a `logging:` on all four
  services. YAML anchors do not cross files, so the one in `docker-compose.yml` could not be
  referenced. Without a cap a container's json-file log grows without bound, which is what filled the
  disk in July 2026. Those four containers have never been created on the host, so this is
  preventive.

### Changed

- The secret scanner is the gitleaks CLI rather than `gitleaks/gitleaks-action`. That action requires
  a licence key for repositories owned by a GitHub Organization, and moving these repositories into
  an `sdwa5` organization is the plan, so the action would stop working at exactly the wrong moment.

### Removed

- `TODO.md` items 1.5, 6.2 and 6.4, all implemented here. Item 7.4 is restated: `ollama` is no longer
  an all-interfaces publish, so `minecraft` 25565 is the only one left and that one is deliberate,
  which turns the `DOCKER-USER` gap into defence in depth rather than a live hole.

### Deployment

- **Pulling this commit on the host deletes `/opt/docker/minecraft-data/server.properties`**, because
  the commit records a deletion and git applies that to the working tree whatever `.gitignore` says
  afterwards. Copy it aside before the pull and put it back after. The image regenerates one from the
  environment, but the keys that come from neither the environment nor a default would silently fall
  back.

## [1.18.0] - 2026-09-08

### Fixed

- **`docs/ssh-hardening.md` claimed the firewall covers a container published on `0.0.0.0`. It does
  not and cannot.** A published port is DNAT'd in `nat/PREROUTING` and traverses `FORWARD`, never
  `INPUT`, and `DOCKER-USER` is an empty `RETURN` on this host. The `INPUT DROP` policy is therefore
  invisible to container traffic. The document now states what the firewall does and does not buy,
  namely host daemons yes and container publishes no.
- The same paragraph asserted that every Docker publish binds `127.0.0.1` and that this compose file
  never published on all interfaces. That was measured from running containers and generalised to the
  file. `minecraft` publishes `25565:25565` and `ollama` publishes `11434:11434` on all interfaces,
  both profile-gated and down at the time.
- `docs/monitoring.md` records that `check_firewall` reads `INPUT` and so cannot see a container
  exposed on `0.0.0.0`.

### Changed

- The IPv6 neighbour-cache hypothesis from 1.17.0 is **refuted by test**. IPv6 was left idle for 25
  minutes, in a window excluding the `:17` health-check cron, and inbound was probed cold with all
  control traffic forced to IPv4. Ping 0% loss and `ssh -6` reachable, identical to the warm probe. The
  single earlier failure was transient with an unknown cause, and the docs say not to open a provider
  ticket on it.
- `docs/ssh-hardening.md` explains why a cold inbound ping increments the ICMPv6 rule by one rather
  than by the number of echo requests, since conntrack treats the exchange as one flow and the rest
  land on `ESTABLISHED,RELATED`. A counter moving by less than the packets sent is normal.

### Added

- `TODO.md` item for the `DOCKER-USER` gap. Closing it needs rules that keep 25565 reachable, because
  `minecraft` is published on purpose, so a blanket drop is wrong.

## [1.17.0] - 2026-09-08

### Fixed

- **The IPv6 conclusion in 1.16.0 was wrong and is withdrawn.** Inbound IPv6 reaches the host. A
  repeat test on 2026-09-08 gave ping 3/3 at 0% loss and 58 ms, a successful `ssh -6` login, and
  `ip6tables` counters that moved, with `tcp dpt:22` and `tcp dpt:443` each counting a SYN and the
  ICMPv6 rule rising by 11. The recommendation to open a Contabo support ticket is removed, since it
  rested on a single failed window treated as a steady state.
- `curl -6 https://[2a02:...]/` returning `000` is recorded as expected rather than a fault. A
  literal-IP URL sends no SNI and Caddy closes the handshake.

### Changed

- `TODO.md` item 7.4 now reads that inbound IPv6 is intermittent with an unknown cause, and says
  explicitly not to open a Contabo ticket on the current evidence. The untested hypothesis is
  neighbour cache expiry, since nothing here emits IPv6 and no AAAA record points at the host, and it
  names the experiment that would confirm it.
- `docs/monitoring.md` no longer calls inbound IPv6 unverified.

### Added

- `docs/ssh-hardening.md` records what the three attempts cost and the two rules that come out of it.
  A negative network result needs repetition before it becomes a conclusion, because a single failed
  window and a permanent fault look identical. And every counter gets checked rather than the
  convenient ones, since the check that missed this filtered the `ip6tables` output to the policy and
  the TCP rules, so an inbound ICMPv6 packet was counted on the line that had been filtered out.

## [1.16.0] - 2026-09-08

### Added

- `docs/backup.md` documents the **Contabo Auto Backup**, a second independent backup that no
  document here knew about. Ten daily whole-VM images of about 18.4 GB, dated 2026-08-29 to
  2026-09-07, taken in a 07:00 to 18:00 UTC+2 window. It fails differently from restic, which is its
  value, and it is driven only from the Contabo panel so nothing here monitors it.
- The same rule as for restic applies to it. A whole-VM image taken while SQLite runs captures
  `vaultwarden-data/db.sqlite3` hot, so restore the vault from `vaultwarden-db-backup/db.sqlite3`.
  The timing happens to cooperate, since the consistent dump is written at 03:50 and the image is
  taken hours later.

### Changed

- Inbound IPv6 is settled and `docs/ssh-hardening.md` says so. RIPEstat reports `2a02:c206::/32`
  announced by AS51167 and seen by 322 of 322 RIS peers since 2020, the Contabo panel address matches
  the host's netplan exactly and its MAC derives to the link-local address the host shows, outbound
  works 6 of 6, and the ICMPv6 `Address unreachable` originates from Contabo's own router. A packet
  cannot elicit an error from the destination network's router without reaching it, so the single
  vantage point was sufficient after all. Everything up to Contabo's edge works and their last hop to
  the VM does not.
- `TODO.md` item 7.4 becomes "open a Contabo ticket" with the evidence, rather than "test it".
- `TODO.md` restore-drill item notes that the Contabo backup has never been restore-tested either, and
  that it restores only as a whole VM.

## [1.15.0] - 2026-09-08

### Added

- `docs/ssh-hardening.md` settles the inbound IPv6 question. Tested from a Mullvad exit in Sweden with
  IPv6 enabled in the tunnel, so a foreign network with confirmed working IPv6. Inbound fails and the
  ICMPv6 `Address unreachable` is generated by `2a02:c205::1eaf`, a Contabo router. A simultaneous
  `tcpdump -ni eth0 ip6` on the VPS captured 0 packets and every `ip6tables` counter stayed at zero,
  so neither the VM's stack nor the firewall discards anything. Replies to VM-initiated flows do
  arrive, which confirms that independently.
- The limit of that result is stated. One vantage point, and Mullvad's own IPv6 is imperfect, so it
  wants confirmation from a second independent network before a Contabo ticket.

### Changed

- Outbound IPv6 is now recorded as 6 of 6 across three rounds against two targets rather than a single
  ping. Single-shot v6 probes gave two contradictory readings here, because a `STALE` neighbour entry
  costs the first packet while it is re-resolved.
- `TODO.md` item 7.4 carries the finding and the next step instead of asking for a test.

### Changed

- `TODO.md` item 7.3 now tracks finishing the emergency access enrolment with a new member, in
  progress since 2026-09-08, rather than asking which remedy to pick. It names how to verify that a
  grantee exists.

### Removed

- `TODO.md` item on the two dormant Vaultwarden accounts. Decided 2026-09-08 to keep both, recorded
  in the parent repo's `docs/services.md`.

## [1.14.0] - 2026-09-08

### Fixed

- **The IPv6 finding in 1.11.0 was wrong and is corrected.** `docs/ssh-hardening.md` claimed inbound
  IPv6 was blocked upstream of this host. Inbound is unverified, not broken. The evidence was an
  `ip6tables` policy counter of zero packets plus `No route to host` from the workstation, and the
  actual cause was the workstation's Mullvad tunnel, which has `IPv6: off` and blocks IPv6 while
  connected. Those ICMPv6 errors were generated locally by the test client's own address. Outbound
  IPv6 from the host works, measured at 0% loss and 7 ms.
- `docs/monitoring.md` no longer rests the firewall check's IPv6 WARN on that claim. It rests on the
  absence of an AAAA record, which is measured, and says to raise it to CRIT if one is published.

### Changed

- `TODO.md` items 7.2 to 7.4 rewritten from measurement rather than assumption. Of the three accounts
  on PBKDF2, only one is in use and the other two are not. The single-owner item now names what is at
  stake and what the two remedies cost. The per-account figures behind that are deliberately not
  written down here, for the reason item 7.2 gives.

### Added

- `TODO.md` item for the two dormant Vaultwarden accounts, and one for settling inbound IPv6.
- `docs/ssh-hardening.md` records the two traps behind the wrong finding. A zero counter on a DROP
  policy is ambiguous between "nothing arrived" and "nothing was sent", and a client must be proven
  capable before anything is concluded about the server.

## [1.13.0] - 2026-09-08

### Changed

- The `admin` account gets neither an SSH key nor deletion. It is removed from the `sudo` and
  `www-data` groups, its password is locked and its shell is `/usr/sbin/nologin`. It keeps no
  `authorized_keys`.
- Its GECOS field now records why it must not be deleted, because `getent passwd` is where someone
  will look before running `userdel`.
- The break-glass procedure names root only. `admin` can no longer log in at the console either, and
  Contabo can reset the root password from the panel, so that route depends on no stored credential.

### Removed

- `TODO.md` item on deciding the fate of the `admin` account.

### Notes

- The decision turns on a uid collision. The Dolibarr image defines its own `www-data` as uid 1000,
  which maps to `admin` on the host, and 3461 files totalling 64 MB under `dolibarr-documents-data`
  and `dolibarr-custom-data` are owned by it. Deleting the account frees uid 1000, `adduser` hands out
  the lowest free uid, and the next account created would silently inherit ownership of every Dolibarr
  document. The account stays to reserve the uid.
- The same collision was the risk. Host uid 1000 is a public-facing container's web server uid and it
  sat in the host's `sudo` group, so anything achieving host execution as that uid would have
  inherited sudo membership.
- Containers resolve uid 1000 through their own `/etc/passwd` and never the host's, so locking the
  password and changing the shell does not affect them. Verified afterwards with 10 uid 1000 processes
  still running, all 3461 files still owned, Dolibarr returning 200 and all three containers healthy.

## [1.12.0] - 2026-09-08

### Added

- `monitoring/vps-health.sh` gains `check_firewall`. It alerts when the IPv4 `INPUT` policy is not
  `DROP`, when fail2ban's `f2b-sshd` jump is missing, and when a port in `FIREWALL_PORTS` is no longer
  accepted. Without it the firewall added in 1.11.0 could disappear unnoticed, because anything that
  flushes `INPUT` leaves a chain that still looks plausible.
- `FIREWALL_PORTS` tunable, default `22 80 443`.
- Six tests in `tests/vps-health.bats` covering an ACCEPT policy, a missing fail2ban jump, a dropped
  service port, an unreadable chain, an open IPv6 policy and several faults at once. `tests/stubs/iptables`
  and `tests/stubs/ip6tables` are new, and `common_setup` now installs a healthy chain by default.
- `docs/monitoring.md` documents the check and why IPv6 is a WARN rather than a CRIT.

### Changed

- A missing `iptables` binary or an unreadable `INPUT` chain is CRIT rather than silently passing. A
  check that cannot see its subject has confirmed nothing, and silence would read as healthy.
- All firewall faults are reported in one line rather than one per run, so a single mail carries the
  whole picture instead of the first problem only.

## [1.11.0] - 2026-09-08

### Added

- `hardening/firewall/sdwa5-firewall.sh` and `sdwa5-firewall.service`. Default-deny `INPUT` for IPv4
  and IPv6, allowing loopback, established and related, ICMP, the Docker bridges and 22, 80 and 443.
  Enabled at boot.
- `hardening/systemd/resolved.conf.d/10-no-llmnr.conf`. Turns LLMNR and mDNS off, which closed 5355
  on TCP and UDP for both families. It was the only unnecessary port open to the internet.
- `docs/ssh-hardening.md` gains a firewall section covering the measured exposure before the change,
  why `iptables-restore` and `iptables-persistent` are not used, the fail2ban flush problem and the
  IPv6 finding.
- `hardening/firewall/sdwa5-firewall.sh` added to the shellcheck list in `tests/run.sh`, which is an
  explicit file list rather than a glob and would otherwise never have covered it.

### Changed

- The firewall is defence in depth rather than a repair. Measured before the change, every Docker
  publish already bound `127.0.0.1`, along with exim4 and the Caddy admin API, so only 22, 80, 443
  and 5355 were public. The value is protection against the next service that binds `0.0.0.0` by
  accident.
- The script rewrites `INPUT` alone instead of restoring a saved table. Docker owns `DOCKER`,
  `DOCKER-USER`, `DOCKER-ISOLATION-*` and a set of `FORWARD` rules and rebuilds them at its own start,
  so a restored snapshot would replay stale copies referring to bridges that may no longer exist. This
  also makes the script idempotent.
- The unit is ordered `Before=fail2ban.service` and restarts fail2ban from `ExecStartPost` when it is
  already running. Flushing `INPUT` removes fail2ban's jump, which would leave SSH unfiltered while
  still looking correct. The `ExecStartPost` is guarded by `is-active` so it is a no-op at boot, and
  uses `--no-block`, because waiting on a unit ordered after this one would deadlock.

### Notes

- IPv6 is unreachable from outside for a reason upstream of this host. It holds
  `2a02:c206:3015:7801::1/64` with a default route and no AAAA record is published. Inbound SSH to the
  address returns `No route to host` from a client with working IPv6, and the `ip6tables` `INPUT`
  policy counter reads 0 packets, so nothing arrives at all. The v6 rules are in place regardless, so
  that publishing an AAAA record later does not expose an unfiltered stack.
- `ip6tables-save` writes an empty file on this host and exits 0, because the nft backend has no `ip6`
  filter table until something creates one, while `ip6tables -S` synthesises the default policies and
  looks normal. An empty restore file is a silent no-op, so an auto-revert built from it protects
  nothing.

### Changed

- `docs/ssh-hardening.md` — `id_ed25519_sdwa5` is in Vaultwarden since 2026-09-08, as item
  `00fceed1-965b-4857-9b91-2d371d0c6662`. It was uploaded by path so the key never passed through a
  command line or the process list, then downloaded again and compared byte-for-byte against the file
  on disk. The open item narrows to the notebook copy alone, which stays open because a rescue console
  cannot fetch a vault item and every client is logged out for a while after a KDF change.

### Added

- `docs/shopware/TODO.md` item 5.4, actual preorders. Binding prepaid orders for merch not yet in
  stock, motivated by financing rather than by the feature itself, since bulk pricing needs capital
  the association does not have before it has sold anything. Distinguishes it from 5.3, which only
  measures interest. Names the three open decisions: when the money is taken, the minimum quantity and
  the refund path if the run does not happen, and the legal wording for a binding prepaid sale, which
  belongs in the same AGB pass as item 13.

## [1.10.0] - 2026-09-07

### Changed

- Back on `vaultwarden/server:latest`. The testing pin from 1.8.0 existed only to get the master
  password changed, that is done, and a tagged release is the right default for a password vault.
  The weekly auto-update tracks releases again, so 1.37.3 will arrive on its own rather than needing
  a version-drift warning as a cue.
- `monitoring/vaultwarden-autoupdate.sh` back to `IMAGE=vaultwarden/server:latest`, matching compose.
  `docs/infrastructure.md` and `docs/monitoring.md` follow.
- `docs/vaultwarden.md` — the testing section is now a record of why it was needed and how to do it
  again, rather than a description of current state. It gains the reason the revert was cheap: the
  testing build applied **no** schema migration, the newest row in `__diesel_schema_migrations` being
  `20260505120000` from 2026-09-01, so the schema matched what 1.37.2 expects and no snapshot restore
  was involved. A build that had applied one would have made the revert a restore instead, losing the
  master password and KDF changes with it, so the check is documented as a precondition.

### Added

- `docs/vaultwarden.md` lists what stays broken on the release, so it is not rediscovered. Master
  password change and reset two-step login are both broken by the same payload change, #7659 and
  #7674. Organisation import into a collection is broken by #7698, confirmed with `.kdbx` through the
  SDK importer where the payload omits `groups` and `users` that Vaultwarden requires but never reads.
  Personal import from a password-protected `.json` export is unaffected, because such an export
  carries neither field, and that is the disaster-recovery path that matters.

### Removed

- `TODO.md` item 7.6, returning to a tagged release, which this release does.

## [1.9.0] - 2026-09-07

### Added

- `docs/vaultwarden.md` — runbook for a mobile client that cannot log in after a password or KDF
  change. The tell is the `devices` table rather than the log: the Android app's `updated_at` predated
  the change by over an hour, a log capture over the attempt window was empty, and no authentication
  had been rejected anywhere, so the failure was entirely local. A locked Bitwarden client holds a
  stale `kdfConfig` and a user key wrapped with the old master key, and never calls the server, so it
  cannot learn that anything changed. Clearing the app's storage and logging in fresh fixed it.
  Records that a second factor and a pending new-device verification were both ruled out, since both
  produce the same symptom.
- `docs/vaultwarden.md` — the rotation performed on 2026-09-07 is recorded in the "Master password and
  KDF" section, together with the fact that `private_key` and `public_key` were unchanged, which is
  the proof that "Rotate account encryption key" was left off.
- `docs/vaultwarden.md` step 7 now warns that the mobile app is expected to refuse the new password at
  its lock screen, so the reader does not read it as a fault and retry.
- `TODO.md` items 7.6 and 7.7: returning to a tagged release once one above 1.37.2 exists, and the
  fact that emergency access is enabled but nobody is enrolled while the SdWa5 org has a single owner,
  which leaves a forgotten master password unrecoverable for all four accounts.

### Changed

- The account now uses Argon2id at 64 MiB, 3 iterations, parallelism 4, verified from the database.
  451 ciphers intact. The other three accounts remain on PBKDF2 600,000, which only their holders can
  change.

## [1.8.0] - 2026-09-07

### Changed

- Vaultwarden runs `vaultwarden/server:testing`, pinned by digest
  `sha256:4d840a0d45e51389297bb69dead79e8a549afa2d7a9d3db3221123a02668e441`, reporting
  `1.37.2-a6c3bd6d`. Changing the master password is broken in the 1.37.2 release: the bundled web
  vault sends Bitwarden's newer payload with `authenticationData` and `unlockData`, while the handler
  still expects `newMasterPasswordHash`, so the request fails with 422 before reaching the database
  and the client shows only "An error has occurred". Upstream issue #7659, duplicate of #7622, fixed
  by PR #7634 around 2026-08-29 and not in any tagged release. Downgrading to 1.37.0 also fixes it and
  was rejected, because it breaks the browser extensions, which is the September 2026 incident already
  recorded in `docs/vaultwarden.md`.
- The pin is a digest rather than the floating `testing` tag on purpose. `testing` tracks main, and a
  floating tag would let the weekly auto-update move this vault onto whatever main-branch happens to
  be, every Sunday, unattended. With a digest, `docker-compose pull` is a no-op.
- `monitoring/vaultwarden-autoupdate.sh` follows the same pin, so it compares the right image rather
  than still inspecting `vaultwarden/server:latest` while compose points elsewhere. Its help text and
  failure mail no longer hardcode the tag.
- `docs/vaultwarden.md` gained a "Temporarily on the testing image" section covering the reason, why
  the digest pin, and the route back. `docs/infrastructure.md` and `docs/monitoring.md` follow.

### Added

- The route back is documented and self-signalling. `monitoring/vps-health.sh` strips the `-a6c3bd6d`
  suffix, so it reads `1.37.2` and stays quiet today. The moment a release above 1.37.2 appears it
  warns that the server is behind, and that warning is the cue to return to `latest`.

### Changed

- `docs/ssh-hardening.md` records that this host is not exposed by the unprotected copies of the old
  keys still on stefan-notebook, because `id_rsa` was removed from its `authorized_keys` and
  `id_ed25519_sdwa5` does not exist on that machine. Replacing the key rather than only adding a
  passphrase to it is what bought that.

- `docs/ssh-hardening.md` and `TODO.md` item 7.2 corrected. `id_ed25519_sdwa5` does belong in
  Vaultwarden, which is the private vault for a private key. The original reasoning, that Vaultwarden
  running on the host the key unlocks makes storing it there circular, only applies when the server
  and every logged-in client are unavailable at once, because Bitwarden clients cache the vault and
  unlock offline. What survives is that a KDF or master password change logs out every client for a
  while, and that a vault item cannot be fetched from a rescue console, so the notebook copy stays on
  the list and the Contabo console remains the break-glass.

## [1.7.0] - 2026-09-07

### Added

- `hardening/sshd_config.d/10-hardening.conf` and `hardening/fail2ban/jail.local`, the deployable host
  SSH configuration, byte-identical to what runs on the VPS. Applied after finding 13,672 failed root
  logins in the previous 24 hours, escalating to several hundred attempts per minute during the work,
  against a host with `PasswordAuthentication yes`, `PermitRootLogin yes`, no firewall and no
  fail2ban. `PasswordAuthentication no`, `PermitRootLogin prohibit-password` and `MaxStartups
  30:50:200` now apply, and `Failed password` went from roughly 180 per minute to zero.
- `docs/ssh-hardening.md`, recording the finding, the change, the verification and the break-glass
  path. Includes the two traps that produce false results when testing this: a reload leaves
  already-forked sshd children on the old config for up to `LoginGraceTime`, and `ssh -i` appends to
  the identity list rather than replacing what the config supplies, so a "key still works" test can
  pass on the wrong key.
- fail2ban with the sshd jail. The Debian default fails to start on this host with "Have not found
  any log file for sshd jail", because sshd logs to journald only and there is no rsyslog or
  `/var/log/auth.log`, so `backend = systemd` is set explicitly. 71 addresses banned in the first
  hour.
- `README.md` gained a "Host access" section and both new documents in the index.
- `docs/infrastructure.md` gained the sshd node and edge in the diagram, the `hardening/` and
  `vaultwarden-db-backup/` directories in the layout, and the daily database copy in the cron table,
  which had been missing since 1.6.0.
- `TODO.md` item 7, the security follow-ups: no firewall at all, the notebook key copy, what to do
  about the `admin` account, the parent repo's `docs/services.md` claiming one Vaultwarden user where
  the database holds four, and the other three accounts still being on PBKDF2.

### Changed

- root's `authorized_keys` on the VPS holds one personal ed25519 key,
  `SHA256:3r0Dk1tFl8W/iHyFC6rsOFbQ1JznqEeP5+06iYug0mA`, instead of the 8196-bit work RSA key
  `sri@sri-VirtualBox` that was previously its only entry. That work key is also used for
  `github.com` and `git.myndc.de`, and a work credential holding sole root on the private box that
  carries the vault is a boundary problem in both directions. The old key is verified rejected.

### Fixed

- `/etc/ssh/sshd_config.d/50-cloud-init.conf` contained `PasswordAuthentication yes` and silently
  overrode the `PasswordAuthentication no` already present at line 57 of `sshd_config`, because the
  `Include` sits at line 12 and sshd uses the first occurrence of a keyword. Editing the main file
  changed nothing. `10-hardening.conf` sorts before the cloud-init file and therefore wins, which
  also survives `cloud-init.service` rewriting its own file on every boot.

### Added

- `docs/vaultwarden.md` — new step 3 in the master password order of operations: memorise the password before changing
  anything, gated on two cold successes on separate days with at least one after a night's sleep rather than on a
  repetition count. Records that the copy stays on paper while learning, because a Bitwarden item would sit in a vault
  still protected by the old password and a master password change re-wraps the user key rather than re-encrypting each
  item, and that neither is a backup. Later steps renumbered to 4 through 8. Amended the same day to
  keep no copy at all rather than a paper one, using `genpass.py --show --verifier` and `--check` from
  the workstation docs, since a password not yet in use costs nothing to lose and only recall needs
  verifying.
- `docs/vaultwarden.md` points at `~/PhpstormProjects/ai/docs/password-strength.md` for the master password length
  analysis, and names the outcome of 18 lowercase characters with at least one digit so the answer is available
  without leaving this repository.

### Fixed

- `monitoring/vps-health.sh` padded the check-name column to 20 characters in the `--dry-run` output
  and in the alert mail body. `vaultwarden_db_backup` is 21, so it pushed the status column out of
  line on that row. Widened to 21.
- `.gitignore` did not cover the `vaultwarden-data.bak-*` snapshots that
  `monitoring/vaultwarden-autoupdate.sh` writes, so the deploy checkout at `/opt/docker` always
  reported a dirty working tree. That makes a clean tree useless as a precondition for the automated
  deploy in `TODO.md` item 1.

## [1.6.0] - 2026-09-03

### Added

- `monitoring/vaultwarden-db-backup.sh`: daily consistent copy of the Vaultwarden database at 03:50,
  ten minutes before the restic run. restic mounted `/opt/docker` read-only and copied
  `vaultwarden-data/db.sqlite3` while Vaultwarden was writing to it, and SQLite in WAL mode spreads a
  commit across the database file and the write-ahead log, so a snapshot taken between the two could
  restore into a torn transaction. The dump now goes through SQLite's online backup API into
  `vaultwarden-db-backup/db.sqlite3`, is verified with `PRAGMA integrity_check` and only then
  replaces the previous copy. Any failure keeps the last verified copy and mails. Vaultwarden keeps
  serving, because the backup API takes a read lock per page batch rather than stopping the
  container.
- `monitoring/vps-health.sh`: new `vaultwarden_db_backup` check, critical when the consistent copy is
  missing or older than `DB_BACKUP_MAX_AGE_HOURS` (26). The existing `backup` check only proved that
  a snapshot was taken, never that the database inside it could be restored, and the dump job is
  silent on success, so nothing would otherwise notice it stopping.
- `monitoring/cron.d/vaultwarden-db-backup`: cron entry, journal tag `vaultwarden-db-backup`.
- `docs/vaultwarden.md`: "Master password and KDF" section. Records that the KDF is an account
  property on the Vaultwarden user row and that changing it touches nothing server-side, the
  Argon2id target of 64 MiB / 3 iterations / parallelism 4 and why memory rather than iterations is
  the knob to raise, the order in which the password and the KDF are changed with a verified login in
  between, the password-protected export as the only usable rollback, and the fact that the forced
  re-login is what triggered the September 2026 extension failure. Also records the break-glass gap,
  since the admin token's plaintext lives in the vault that the token would be needed to recover.
- `tests/vaultwarden-db-backup.bats` and a `sqlite3` stub: 11 new cases covering a successful publish,
  file permissions, a missing `sqlite3`, an unreadable source, a failed dump and a dump that fails its
  integrity check. The suite is now 62 cases.

### Changed

- `docs/backup.md` now states that a restore takes the vault from `vaultwarden-db-backup/db.sqlite3`
  rather than from the hot `vaultwarden-data/db.sqlite3`, and documents verifying the restored
  database before trusting it.

### Fixed

- `monitoring/vps-health.sh` reported "Vaultwarden 1.37.2 is behind 1.37.2" and mailed 8 problems for
  a healthy server. Two defects, found by the first real cron run on 2026-09-02.
  - The release lookup scraped the GitHub response for anything version-shaped, which also matched
    the release notes. The 1.37.2 notes mention 2026.8.0, 1.37.1 and 1.37.0, so the comparison value
    became seven lines and `sort -V` picked 2026.8.0. It now reads the `tag_name` value itself, on
    pretty and on compact JSON, accepts an optional `v` prefix, and rejects anything that is not a
    dotted version.
  - A check emitting more than one line turned every extra line into a phantom check with an empty
    status, which was alerted on and written to the state file. Check output is now normalised to
    exactly one tab-separated line by `emit`, and an unrecognised status is reported as a malformed
    check rather than silently treated as a fault.
- `monitoring/vps-health.sh` never removed state records for keys a run no longer produces, so a
  renamed check or a malformed run left records behind forever. Recovery is only detected for keys
  still present in the results, so nothing else would have cleared them.

- `monitoring/vps-health.sh` and `monitoring/vaultwarden-autoupdate.sh` read the web vault version
  instead of the server version. `vaultwarden --version` prints both, and taking the last
  version-shaped number picked up `Web-Vault 2026.7.0`, which sorts above every 1.x release, so the
  drift check would have reported an outdated server as current. Caught on the first live dry run.
  Both now match the `Vaultwarden` line specifically, with a regression test.

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

- The Bitwarden browser extension additionally kept failing after the server upgrade, reporting
  "Invalid master password" for a login the server logged as successful. Cause was stale extension
  storage built against the old server, which survives both a logout and a browser restart. A full
  reinstall cleared it and the extension works on 2026.8.0, so no client is pinned. Confirmed on the
  server by the `GET /api/sync => 200 OK` that every failed attempt was missing. Disabling the
  organization policies was tried on 2026-09-01 and reverted; the upstream symptom in
  [#7635](https://github.com/dani-garcia/vaultwarden/issues/7635) reproduces without them. The full
  triage order is in `docs/vaultwarden.md`.

## [1.4.6] - 2026-07-22

### Added

- `docs/shopware/privacy-tos-review-2026-07-22.md`: an in-depth AI-assisted DSGVO/AGB
  compliance review of the live Impressum, Datenschutzerklärung, AGB, and Widerrufsrecht
  CMS pages plus the cookie-consent banner wording — best-effort, not legal advice (a
  professional lawyer review is out of budget). Four independent Opus review passes with
  live web verification of volatile facts (EU ODR platform status, EU-US Data Privacy
  Framework, UK adequacy decision), cross-checked against each other and the org's own
  docs. **The document and its findings moved to Google Drive on 2026-09-13 and are no
  longer in this repository or its history — see 1.32.0.** The work item that applies them
  is item 6 of `docs/shopware/TODO.md`.

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
