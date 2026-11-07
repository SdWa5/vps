# Jami Web (always-on Jami peer)

`jami_web` runs [Jami Web](https://git.jami.net/savoirfairelinux/jami-web), the web client of the Jami
messenger, with its native daemon. It is an ordinary Jami peer, not a server other peers depend on.
It carries the owner's Jami account as a linked device, so messages and group conversations reach
the account and stay synced while the owner's own devices are off. Jami needs no federation and no
server for anyone else. Members run their own Jami app and reach this peer through the public
OpenDHT network, by Jami ID or by a username on `ns.jami.net`. The member view is in the parent
repository's [services.md](https://github.com/SdWa5/docs/blob/main/docs/services.md#jami-messenger).

## Access

The UI listens on `127.0.0.1:8008` only and has no public domain. Open it through an SSH tunnel from
a workstation, then browse to `http://localhost:8008`:

```bash
ssh -N -L 8008:127.0.0.1:8008 root@sdwa5.org
```

A public `jami.sdwa5.org` is a proposal in [TODO.md](../TODO.md), for the day someone besides the
owner keeps an account on this peer. Jami Web's self-signup (`POST /api/auth/new-account`) is open
whenever local authentication is on, so that step blocks it at Caddy.

## Image

The image is built on the host from [`jami-web/`](../jami-web/) and is in no registry, so the service
has `pull_policy: never`. Upstream recommends the npm package, which ships the prebuilt daemon
(`@savoirfairelinux/jami-core-linux-x64`, glibc 2.39, hence Debian 13). Upstream's own Dockerfile
builds from source and runs as root. This image installs the locked package on
`node:26-trixie-slim`, pinned by digest, and runs as `node` (uid 1000).

- **Runtime packages.** Upstream's list plus `libvdpau1`, which jami-core 0.5.4 still links. The
  build fails if `ldd` reports a missing library for `jamid.node`. `ca-certificates` is required,
  because without it the daemon's HTTPS calls fail and every username lookup reports the name as
  free (upstream issue #273)
- **Lock.** `jami-web/package-lock.json` was resolved with `npm install --package-lock-only
  --before=<three days ago>`, matching the three-day cooldown Dependabot keeps
  ([maintenance.md](maintenance.md#update-proposals)). `@savoirfairelinux/jami-web-common` is
  declared as `*` upstream and would otherwise follow every new release
- **Install scripts.** npm 11 skips argon2's install script. It only checks for a prebuilt binary,
  and the build loads `argon2` once to prove the prebuild works
- **Tag.** `localhost/sdwa5-jami-web:<jami-web version>-N`. `tests/compose.bats` keeps the version
  equal to `jami-web/package.json` and the lock

### Updates

Dependabot watches the base image digest (`docker`) and the package (`npm`) in `/jami-web` weekly.
A pull request fails `tests/compose.bats` until the compose tag is bumped in it, to
`<new version>-1` for a package bump or to `-N+1` for a new base image digest. Regenerate the lock
with the command in the next section when a bump changes more than the one package. After the merge,
on the host:

```bash
cd /opt/docker && git pull --ff-only && docker compose up -d --build jami_web
docker exec jami_web jami-web doctor
```

`doctor` reports `Server port: port 8080 is already in use` while the server runs, because it checks
whether it could start a second one. Every other line must be a check mark.

### Building locally

```bash
docker run --rm --platform linux/amd64 -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/jami-web:/w" -w /w \
    node:26-trixie-slim npm install --package-lock-only --no-audit --no-fund \
    --before="$(date -u -d '3 days ago' +%Y-%m-%dT00:00:00Z)"
docker build -t localhost/sdwa5-jami-web:0.2.3-1 jami-web
docker run --rm localhost/sdwa5-jami-web:0.2.3-1 jami-web --help
```

## Data

`jami-web-data/` (700, uid 1000) is the container's `/data` and its `HOME`, so the one bind mount holds
both locations upstream says to back up.

| Path in `jami-web-data/` | Content |
|---|---|
| `jami-web/.env` | JWT signing keys; losing them only ends the web sessions |
| `jami-web/admin.json` | admin account (argon2id hash) and server configuration |
| `jami-web/accounts.json`, `passkeys.json`, `uploads/` | web logins, passkeys, uploaded files |
| `.local/share/jami/<account id>/` | the daemon's account archive, device key and conversation repositories |

restic backs up all of `/opt/docker`, this directory included, without any step of its own. Upstream
asks for a stopped service or a snapshot for a consistent copy, which this peer does not need: it is
one linked device of the owner's account and holds nothing the owner's other devices lack for longer
than they are offline. **Restore by linking a new device, not from restic**, and revoke the old device
from another device's account settings. The restic copy holds a device key, so a leaked backup also
means revoking this device.

## Setup

On the host, once, after the first deploy:

```bash
cd /opt/docker
install -d -o 1000 -g 1000 -m 700 jami-web-data
tools/secrets/write-secret-files.sh jami_web_admin_password=random
docker compose build jami_web && docker compose up -d jami_web
docker exec -i jami_web sh -c 'JAMI_WEB_ADMIN_PASSWORD="$(cat)" exec jami-web setup -y --enable-local --disable-guest --disable-openid --disable-jams --nameserver https://ns.jami.net' < secrets/jami_web_admin_password
docker compose restart jami_web
docker exec jami_web jami-web config --json    # lastWizardState complete, guest, OpenID and JAMS off
```

The admin password stays in `secrets/` and is mounted nowhere, see
[infrastructure.md](infrastructure.md#secrets).

### Linking the owner's account

1. Open the tunnel and `http://localhost:8008`, and choose to link an existing account.
2. Confirm the shown code on one of the owner's devices under "Link new device".
3. Set the Jami Web login password and keep it in Vaultwarden.

`docker exec jami_web jami-web accounts list` then shows the account.

Both were tested on 2026-11-07. The link ran through Jami's relay, as expected without inbound UDP. For the
offline test, a throwaway account in a separate daemon sent a message while the notebook's daemon was stopped, and
then went offline itself. The restarted notebook had fetched the message two seconds later, and this peer was the
only device that could have provided it.

### An account for a trusted person

People in general run their own Jami. For someone the owner knows well, an account on this peer is
fine on request:

```bash
docker exec -it jami_web jami-web accounts create
```

The person logs in through the tunnel with the account hash and the password. A second person
depending on this peer is the trigger for the public domain in [TODO.md](../TODO.md).

## If the VPS is compromised

Revoke this peer's device from the owner's notebook or phone under the account's linked devices. The
account itself stays valid on every other device.

## Known limits

- Jami Web is young (0.2.x) and changes fast. 0.2.3 cannot create groups or invite members, which
  0.2.4 added, so groups are created on the phone or notebook
- Calls are untested. The firewall accepts no inbound UDP, so calls depend on ICE through outbound
  connections and the TURN relay `turn.jami.net`. A call to the account also rings this device
- Behind a proxy all logins share one rate-limit bucket, because Jami Web sets no `trust proxy`. Over
  the tunnel the only client is the tunnel itself
- Memory was 92 MiB with the owner's account linked, measured on the VPS on 2026-11-07
