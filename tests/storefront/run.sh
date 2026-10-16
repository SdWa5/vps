#!/usr/bin/env bash
#
# Check the rendered storefront layout with Playwright, inside Docker.
#
# The suite asserts what the theme's alignment fixes measured: the header
# settings, the offcanvas settings and donate link share one centre line, and
# the homepage tiles end at their padding. Two element screenshots cover what a
# box cannot, such as the dropdown caret.
#
# It needs a running Shopware, so it is not part of tests/run.sh and CI. A push
# would otherwise be judged by what is deployed rather than by what was pushed.
# Run it after a theme deploy, or against the local mirror before one. The
# requests are plain page loads, the same as any visitor makes.
#
# Usage:
#   tests/storefront/run.sh                       all projects against sdwa5.org
#   tests/storefront/run.sh --update-snapshots    rewrite the baselines after an intended design change
#   tests/storefront/run.sh --project phone-dark  any other playwright test argument
#
# Environment:
#   SDWA5_STOREFRONT_URL   storefront to test, default https://sdwa5.org,
#                          http://localhost:8090 for tools/shopware/dev-instance.sh

set -euo pipefail

# The tag labels the version, the index digest fixes the image. It has to match
# @playwright/test in package.json, because the browsers come with the image.
IMAGE='mcr.microsoft.com/playwright:v1.63.0-noble@sha256:eff16c30e6f3f4af0a03fa4b706120d5e9b0891c344a27d64559aff5900a4a27'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Host network so the mirror on 127.0.0.1 is reachable. --ipc=host keeps
# Chromium from running out of shared memory, as Playwright's Docker guide asks.
docker run --rm --init --ipc=host --network host \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e SDWA5_STOREFRONT_URL \
    -v "$DIR:/work" -w /work \
    "$IMAGE" \
    sh -c 'npm ci --no-audit --no-fund --loglevel=error && npx playwright test "$@"' sh "$@"
