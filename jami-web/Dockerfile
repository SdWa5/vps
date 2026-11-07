# Jami Web for the SdWa5 VPS peer, see docs/jami.md.
#
# Upstream recommends the npm package, which ships the prebuilt native daemon. Its own Dockerfile builds
# from source and runs as root; this one installs the locked npm package and runs as the node user. The
# runtime packages are upstream's list. ca-certificates is required: without it the daemon's HTTPS
# calls fail and username lookups report every name as free (upstream issue #273). libvdpau1 is not
# on upstream's list any more, but jami-core 0.5.4's jamid.node still links it (ldd, 2026-11-07); the
# ldd check below fails the build whenever a library is missing.
FROM node:26-trixie-slim@sha256:5adad64f9a1fca2d51972caa65983634c8a774eb300d72b20f7f2a0f60368072

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates libexpat1 libpulse0 libva-drm2 libva-x11-2 libvdpau1 alsa-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/jami-web
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force \
    && ! ldd node_modules/@savoirfairelinux/jami-core-linux-x64/jamid.node | grep 'not found' \
    && node -e "require('argon2')"

# HOME under /data puts the daemon's identities and conversations into /data/.local/share/jami, so the
# one bind mount holds both locations upstream says to back up.
ENV NODE_ENV=production \
    JAMI_WEB_DATA_DIR=/data/jami-web \
    HOME=/data \
    PORT=8080 \
    PATH=/opt/jami-web/node_modules/.bin:$PATH

USER node
EXPOSE 8080
CMD ["jami-web"]
