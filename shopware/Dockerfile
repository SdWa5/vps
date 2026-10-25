# The sdwa5.org shop (docs/shopware/image.md). tools/shopware/image.sh builds it
# from a git export: this directory is the main context, and the named context
# `project` is shopware-html-data/ with the composer files, config and theme.
FROM ghcr.io/shopware/shopware-cli:0.19.5-php-8.5@sha256:864044741e24e3e8a6a97bf9f81964560c1cfd446bbdf984aef8b4083b82cdf0 AS build
WORKDIR /src
COPY --from=project composer.json composer.lock symfony.lock .shopware-project.yml ./
COPY --from=project config ./config
COPY --from=project custom/static-plugins/SdWa5Theme ./custom/static-plugins/SdWa5Theme
COPY . ./
# auth.json carries the packages.shopware.com token and never reaches a layer.
RUN --mount=type=secret,id=composer_auth,dst=/src/auth.json \
    --mount=type=cache,target=/root/.composer \
    --mount=type=cache,target=/root/.npm \
    /usr/local/bin/entrypoint.sh shopware-cli project ci /src
# Shopware's own guard against its web installer, besides SHOPWARE_SKIP_WEBINSTALLER.
RUN touch install.lock

FROM ghcr.io/shopware/docker-base:8.5.12-frankenphp@sha256:db6b49d54cd91337fb1d35be75d6d73c4be6471f695897d53f9a095cfe4e4647
USER root
# The shop listens on 8000, so frankenphp needs no file capability, and with one it
# cannot start under cap_drop: [ALL]. Caddy on the host writes the access log with
# redaction and a 14-day retention, so this Caddy writes none (docs/shopware/image.md#runtime).
RUN setcap -r /usr/local/bin/frankenphp \
 && sed -i -E '/^\s*log\s*$/d' /etc/caddy/Caddyfile \
 && ! grep -qE '^\s*log\b' /etc/caddy/Caddyfile
USER www-data
# Caddy's admin API would listen on localhost:2019, in reach of a server-side request
# from PHP. The base presets an admin password for a fresh install, which the deployment
# helper's pre-install hook refuses anyway, and the security recheck would report the
# preset. DO_NOT_TRACK stops the helper's telemetry, and only a rebuild updates this image.
ENV CADDY_GLOBAL_OPTIONS="admin off" \
    INSTALL_ADMIN_PASSWORD= \
    DO_NOT_TRACK=1 \
    SHOPWARE_DISABLE_UPDATE_CHECK=1
# Replaces the inherited check, which polls the admin API that admin off closes.
HEALTHCHECK --start-period=300s --interval=30s --timeout=10s --retries=3 \
    CMD curl -fs --max-time 5 http://127.0.0.1:8000/api/_info/health-check || exit 1
COPY --from=build --chown=82 --link /src /var/www/html
