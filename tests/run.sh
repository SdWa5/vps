#!/usr/bin/env bash
#
# Run the monitoring test suite and shellcheck. Everything happens in Docker,
# so nothing has to be installed on the host.
#
# The bats image is Alpine and ships busybox date, which cannot parse the
# timestamp formats the scripts read out of the restic log. GNU coreutils is
# installed into the throwaway container so the test environment matches the
# Debian VPS. jq comes along for the same reason: the scripts in tools/shopware/
# build their JSON payloads with it, and so do their suites' fixtures. git is real
# rather than stubbed for tools/dolibarr/deploy-module.sh, whose suite clones a
# throwaway repository.
#
# Usage: tests/run.sh [bats arguments]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Exact tags and index digests preserve the measured test runtimes on every host.
CI_BATS_IMAGE='bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f'
CI_SHELLCHECK_IMAGE='koalaman/shellcheck:v0.11.0@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d'
CI_PHP_IMAGE='php:8.2.33-cli@sha256:0ca296c0ae905940c0a333a15de437f3acaa81743333a9437221f6a44e3f0981'
CI_PYTHON_IMAGE='python:3.12.15-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1'

echo "== bats =="
docker run --rm -v "$REPO_ROOT:/code" -w /code --entrypoint sh "$CI_BATS_IMAGE" \
    -c "apk add --no-cache coreutils jq git >/dev/null 2>&1 && bats ${*:-tests/}"

echo
echo "== shellcheck =="
docker run --rm -v "$REPO_ROOT:/mnt" -w /mnt "$CI_SHELLCHECK_IMAGE" -x \
    monitoring/lib.sh \
    monitoring/vps-health.sh \
    monitoring/vaultwarden-autoupdate.sh \
    monitoring/vaultwarden-db-backup.sh \
    monitoring/database-backup.sh \
    monitoring/database-restore-check.sh \
    monitoring/security-recheck.sh \
    monitoring/shopware-worker.sh \
    monitoring/chimodiazz-deploy.sh \
    restic/entrypoint.sh \
    restic/backup.sh \
    hardening/firewall/sdwa5-firewall.sh \
    tools/dolibarr/deploy-module.sh \
    tools/dolibarr/dev-instance.sh \
    tools/dolibarr/lib.sh \
    tools/dolibarr/mcp-setup.sh \
    tools/dolibarr/module-setup.sh \
    tools/dolibarr/rehearse-upgrade.sh \
    tools/dolibarr/doli.sh \
    tools/dolibarr/set-address.sh \
    tools/dolibarr/sync-pm.sh \
    tools/paperless/lib.sh \
    tools/paperless/dev-instance.sh \
    tools/paperless/setup.sh \
    tools/paperless/visibility-check.sh \
    tools/mariadb/recreate-foreign-keys.sh \
    tools/mariadb/reset-root-password.sh \
    tools/mariadb/reset-root-password.inner.sh \
    tools/compose.sh \
    tools/shopware/lib.sh \
    tools/shopware/create-products.sh \
    tools/shopware/edit-slots.sh \
    tools/shopware/check-order-mail.sh \
    tools/shopware/dev-instance.sh \
    tools/shopware/images/shop-images.sh \
    tools/shopware/print-cost/print-cost.sh \
    tools/shopware/print-cost/slice-inner.sh \
    tools/shopware/set-address.sh \
    tools/shopware/set-homepage-sections.sh \
    tools/shopware/sync-production-cost.sh \
    tests/run.sh \
    .github/scripts/install-ci-tool.sh \
    tests/test_helper.bash \
    tests/stubs/* \
    tests/stubs-recheck/*

docker run --rm -v "$REPO_ROOT:/code:ro" -w /code "$CI_PHP_IMAGE" \
    php tests/shopware-database-client.php

echo
echo "== python =="
# The versions the shop-images image resolves for rembg 2.0.84.
docker run --rm -v "$REPO_ROOT:/code:ro" -w /code -e PIP_ROOT_USER_ACTION=ignore "$CI_PYTHON_IMAGE" \
    sh -c "pip install -q --disable-pip-version-check numpy==2.5.4 pillow==12.3.0 \
        && python -I -B tests/shopware-merch-tools.py \
        && python -B -m unittest discover -s .github/tests -v"

echo
echo "All checks passed."
