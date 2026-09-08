#!/usr/bin/env bash
#
# Run the monitoring test suite and shellcheck. Everything happens in Docker,
# so nothing has to be installed on the host.
#
# The bats image is Alpine and ships busybox date, which cannot parse the
# timestamp formats the scripts read out of the restic log. GNU coreutils is
# installed into the throwaway container so the test environment matches the
# Debian VPS.
#
# Usage: tests/run.sh [bats arguments]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "== bats =="
docker run --rm -v "$REPO_ROOT:/code" -w /code --entrypoint sh bats/bats:latest \
    -c "apk add --no-cache coreutils >/dev/null 2>&1 && bats ${*:-tests/}"

echo
echo "== shellcheck =="
docker run --rm -v "$REPO_ROOT:/mnt" -w /mnt koalaman/shellcheck:stable -x \
    monitoring/lib.sh \
    monitoring/vps-health.sh \
    monitoring/vaultwarden-autoupdate.sh \
    monitoring/vaultwarden-db-backup.sh \
    monitoring/shopware-worker.sh \
    hardening/firewall/sdwa5-firewall.sh \
    tests/run.sh \
    tests/test_helper.bash \
    tests/stubs/*

echo
echo "All checks passed."
