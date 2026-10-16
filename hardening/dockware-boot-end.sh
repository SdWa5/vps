#!/bin/sh
# Stops the development services a dockware container starts on every boot.
#
# dockware is a development image. Its entrypoint starts sshd with password
# authentication and dockware's default root and dockware passwords, and
# mailcatcher, before it hands over. Measured 2026-10-16 in both shops: neither
# port is published, but any process inside the container could reach them, and
# an application container has no use for sshd at all. Access goes through
# `docker exec`, as the CIS Docker Benchmark asks ("Ensure sshd is not run within
# containers"). The complete answer is a production image instead of dockware,
# which TODO.md tracks.
#
# dockware runs /var/www/boot_end.sh with `sh` near the end of its entrypoint,
# after sshd and mailcatcher are up, as www-data with passwordless sudo. Compose
# mounts this file there read-only. The entrypoint runs under `set -e`, so this
# script always exits 0 and reports a failure on stderr instead of stopping the
# shop from booting. monitoring/security-recheck.sh notices a surviving sshd.
#
# mailcatcher is stopped only where SDWA5_STOP_MAILCATCHER=1 is set. A shop whose
# mailer still falls back to .env's MAILER_DSN=smtp://127.0.0.1 hands its mail to
# mailcatcher, and stopping it there would turn silently caught mail into send
# errors.

# Waits up to five seconds for no process to match the pgrep arguments, because
# a stop only sends SIGTERM and pgrep right after it still sees the process.
gone() {
    i=0
    while sudo pgrep "$@" >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -gt 10 ] && return 1
        sleep 0.5
    done
    return 0
}

sudo service ssh stop >/dev/null 2>&1 || true
if ! gone -x sshd; then
    echo "SDWA5: sshd still running after 'service ssh stop'" >&2
else
    echo "SDWA5: sshd stopped"
fi

if [ "${SDWA5_STOP_MAILCATCHER:-0}" = 1 ]; then
    # The bracket keeps the pattern from matching sudo's own command line.
    sudo pkill -f 'bin/[m]ailcatcher' >/dev/null 2>&1 || true
    if ! gone -f 'bin/[m]ailcatcher'; then
        echo "SDWA5: mailcatcher still running" >&2
    else
        echo "SDWA5: mailcatcher stopped"
    fi
fi

exit 0
