# Chimo Diazz

Artist website at <https://chimodiazz.sdwa5.org>, hosted here as a favour rather than as an SdWa5
service. The site itself is developed in the private repository `chimodiazz/website`, which this host
pulls with its own read-only deploy key.

**As of 2026-09-15 the subdomain serves a static placeholder and no container runs.** Everything
below the placeholder section describes a slot that is prepared but deliberately switched off.

## Routing

| Domain                 | Upstream                                    | State                      |
|------------------------|---------------------------------------------|----------------------------|
| `chimodiazz.sdwa5.org` | `file_server` over `chimodiazz-placeholder/` | live                       |
| `chimodiazz.sdwa5.org` | `https://127.0.0.1:8444`                     | after the container starts |

The A record already pointed at this host before any of this existed. Measured 2026-09-15:
`chimodiazz.sdwa5.org` resolved to the same address as `sdwa5.org`, and HTTPS failed with
`tlsv1 alert internal error`, which is what Caddy does for a name it has no site block for. Adding
the block is therefore all that was needed for the certificate.

## The placeholder

`chimodiazz-placeholder/index.html` is a single self-contained file with no external resources,
tracked in this repository and served straight off disk by Caddy. It is the only `file_server` block
in the Caddyfile; every other site here is a `reverse_proxy` to a loopback port.

It lives under `/opt/docker/`, so the daily restic backup takes it along. `/opt/docker` is `755
root:root`, which is why the `caddy` user can read it without any permission change.

Editing it is a `git pull` on the host plus nothing else — Caddy serves the file directly and needs
no reload for a content change.

## How the site's code reaches this host

`chimodiazz/website` is private and owned by someone else. GitHub refuses the same deploy key on two
repositories, so the key this host already uses for `SdWa5/vps` could not be reused.

- Key: `/root/.ssh/id_ed25519_chimodiazz_20260915`, ed25519, no passphrase, generated on this host on
  2026-09-15 and never transported anywhere. Fingerprint
  `SHA256:KAVEnhxAUwt4Hi/QFlrcMXNTAiVugeWDBFmM3jJo/go`.
- Registered on `chimodiazz/website` as a **read-only** deploy key. This host never writes there.
- Reached through the alias `github-chimodiazz` in `/root/.ssh/config`, which pins that one key with
  `IdentitiesOnly yes`, exactly as the `github.com` entry does for `SdWa5/vps`. Without
  `IdentitiesOnly` ssh offers every key it can find and GitHub answers as whichever repository the
  first accepted key belongs to.
- Verified 2026-09-15: `ssh -T github-chimodiazz` answers `Hi chimodiazz/website!` while
  `ssh -T github.com` still answers `Hi SdWa5/vps!`.

Checkout target is `/opt/docker/chimodiazz-src`, a nested git repository that this repository ignores
rather than tracks, because its history is not ours to carry.

```bash
git clone github-chimodiazz:chimodiazz/website.git /opt/docker/chimodiazz-src
cd /opt/docker/chimodiazz-src && git pull --ff-only    # later updates
```

**Nothing notices when this key dies.** The `git_remote` health check watches the `SdWa5/vps` key
only. That check exists because the first deploy key kept expiring silently, so the same trap is open
here — see [monitoring.md](monitoring.md) and [ssh-hardening.md](ssh-hardening.md).

## The container, defined and switched off

`docker-compose.projects.yml` holds `chimodiazz_shopware`: one `dockware/shopware:6.7.11.1`
container, the same exact pin as the `sdwa5.org` instance. dockware bundles PHP, the web server and
MySQL in one image, which is how Shopware already runs on this host, so both instances stay the same
shape and a Shopware upgrade is one decision rather than two.

It is gated behind `profiles: ["chimodiazz"]`. A bare `docker-compose -f docker-compose.projects.yml
up -d` must not bring up an empty shop carrying dockware's default credentials on a public subdomain.

Mounts:

| Host path                                              | Container path                                 | Why                                           |
|--------------------------------------------------------|------------------------------------------------|-----------------------------------------------|
| `chimodiazz-mysql-data/`                                | `/var/lib/mysql`                               | database, gitignored                          |
| `chimodiazz-html-data/`                                 | `/var/www/html`                                | Shopware web root, gitignored                 |
| `chimodiazz-src/shopware/custom/plugins/ChimodiazzTheme` | `/var/www/html/custom/plugins/ChimodiazzTheme` | the theme, mounted so a `git pull` updates it |

The theme mount is read-write on purpose: Shopware's storefront build writes into the plugin's own
`dist` directory, and a read-only mount breaks it.

## The two data directories have to be seeded first

**A bind mount is not filled from the image, and both of these mounts need what is in the image.**
Measured on 2026-09-15 against `dockware/shopware:6.7.11.1` on this host:

- `/var/www/html` contains exactly one file in the image, `shopware.tar.zst`. `/entrypoint.sh` line
  144 unpacks it, but only inside `if [ -f "$swCompressedFile" ]`. A bind mount over that path hides
  the archive, the condition is false, and the container comes up with an empty web root and no
  error about it.
- `/var/lib/mysql` is a populated MySQL data directory in the image. An empty bind mount replaces it
  with nothing.

A named volume would not have this problem, because Docker seeds one from the image on first use.
Bind mounts are still the right shape here: it is what the `sdwa5.org` instance uses, and restic
backs up `/opt/docker` rather than Docker's volume store. The `shopware-html-data/` directory that
instance uses was filled once, years ago, which is why the trap has never been visible on this host.

So, before the first start:

```bash
cd /opt/docker
mkdir -p chimodiazz-html-data chimodiazz-mysql-data
cid="$(docker create dockware/shopware:6.7.11.1)"
docker cp "$cid:/var/www/html/." chimodiazz-html-data/
docker cp "$cid:/var/lib/mysql/." chimodiazz-mysql-data/
docker rm "$cid"
```

The archive is copied rather than unpacked on purpose. The entrypoint unpacks it into the mounted
directory on first start and sets the file ownership Apache needs while doing so.

## Bringing it up, once the site is ready

1. Seed the two directories as above, then
   `cd /opt/docker && docker-compose -f docker-compose.projects.yml --profile chimodiazz up -d`
2. **Change dockware's default administrator credentials before the next step.** They are published
   in dockware's own documentation.
3. Install and activate the theme:
   `docker exec chimodiazz_shopware php bin/console plugin:refresh && php bin/console plugin:install --activate ChimodiazzTheme && php bin/console theme:compile`
4. Swap the Caddy block from `root`/`file_server` to the `reverse_proxy` shown in the Caddyfile
   comment, then `install -m 644 /opt/docker/Caddyfile /etc/caddy/Caddyfile && systemctl reload caddy`
5. Add `chimodiazz_shopware` to `EXPECTED_CONTAINERS` in `monitoring/vps-health.sh`.
6. Add a cron file `monitoring/cron.d/chimodiazz-worker` calling the existing
   `monitoring/shopware-worker.sh` with `SERVICE=chimodiazz_shopware` and its own `flock` lock.
   Without it the scheduled tasks stop and nothing says so, which is exactly what happened to the
   `sdwa5.org` instance for 47 days in 2026 — see [monitoring.md](monitoring.md).

Memory measured on the host on 2026-09-15 before any of this: 5937 MB total, 2054 MB used, 3883 MB
available, with the existing Shopware container at 1.01 GiB. A second instance of the same shape
fits, and it is the largest single thing this host would then be running twice.

## Monitoring

`chimodiazz=https://chimodiazz.sdwa5.org/` is in the built-in `HEALTH_URLS` default, so the hourly
check watches the subdomain already. It passes against the placeholder because that returns 200.

`EXPECTED_CONTAINERS` is deliberately unchanged while the container is profile-gated, otherwise every
run would report a missing container.

## Backup

`chimodiazz-placeholder/` and `chimodiazz-src/` sit under `/opt/docker` and are picked up by the
daily restic run. So would `chimodiazz-html-data/` and `chimodiazz-mysql-data/` once they exist, and
the MySQL directory carries the same live-file caveat as the `sdwa5.org` one — see
[backup.md](backup.md).
