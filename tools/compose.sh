#!/usr/bin/env bash
# Picks the Compose command for this host. Sourced, not executed.
#
# Compose v2 is the `docker compose` CLI plugin, which docker-ce ships. Debian 12's
# docker.io has only v1, `docker-compose` 1.29.2, and docker-ce has no
# `docker-compose` at all. Preferring the plugin and falling back to v1 lets the
# same scripts run on either. Measured 2026-10-15: the VPS still had no plugin,
# `docker compose version` exited 1 there.
#
# A DOCKER_COMPOSE set by the caller wins, so tests and one-off runs can pin either.
# Callers expand $DOCKER_COMPOSE unquoted, so "docker compose" splits into two words.

if [[ -z "${DOCKER_COMPOSE:-}" ]]; then
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi
fi
