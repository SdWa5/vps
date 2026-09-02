#!/usr/bin/env bash
#
# Consistent Vaultwarden database copy for the restic backup.
#
# restic mounts /opt/docker read-only and copies vaultwarden-data/db.sqlite3
# while Vaultwarden is writing to it. SQLite in WAL mode spreads a commit across
# the database file and the write-ahead log, so a copy taken between the two can
# restore into a torn transaction. Nothing warns about it. The damage only
# surfaces on the day the restore is actually needed.
#
# This job writes a consistent copy through SQLite's own online backup API into
# vaultwarden-db-backup/, which restic then picks up as an ordinary file. The
# backup API takes a read lock per page batch rather than stopping the
# container, so Vaultwarden keeps serving throughout.
#
# The hot copy in vaultwarden-data/ stays in the snapshot as well. It costs
# nothing and the consistent copy sits next to it, so a restore has both.
#
# Runs from /etc/cron.d/vaultwarden-db-backup at 03:50, ten minutes before the
# restic backup at 04:00.
#
# Usage:
#   vaultwarden-db-backup.sh              dump, verify, publish
#   vaultwarden-db-backup.sh --dry-run    report what would happen, change nothing
#   vaultwarden-db-backup.sh --help

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

SOURCE_DB="${SOURCE_DB:-$COMPOSE_DIR/vaultwarden-data/db.sqlite3}"
BACKUP_DIR="${BACKUP_DIR:-$COMPOSE_DIR/vaultwarden-db-backup}"
DEST_DB="${DEST_DB:-$BACKUP_DIR/db.sqlite3}"
SQLITE="${SQLITE:-sqlite3}"

DRY_RUN=0

# Mail if possible, log otherwise, and always exit non-zero. A silent failure
# here is the whole problem this job exists to remove, so it never exits 0 on a
# path that did not publish a verified copy.
fail() {
    local subject="$1" body="$2"
    send_mail "[sdwa5] $subject" "$body" || log "$subject"
    exit 1
}

# A dump that cannot be opened and read back is not a backup. integrity_check
# walks the whole file, which is cheap on a database this size and is the only
# thing that distinguishes a real copy from a truncated one.
verify() {
    local db="$1" result
    result="$($SQLITE "$db" 'PRAGMA integrity_check;' 2>&1)"
    [[ "$result" == "ok" ]]
}

usage() {
    cat <<'USAGE'
vaultwarden-db-backup.sh - consistent Vaultwarden database copy for restic

Writes vaultwarden-data/db.sqlite3 to vaultwarden-db-backup/db.sqlite3 through
SQLite's online backup API, verifies it with PRAGMA integrity_check and only then
replaces the previous copy. Vaultwarden keeps running.

Runs at 03:50, ten minutes before the restic backup at 04:00, so every snapshot
contains a database that is safe to restore. Mails on any failure and leaves the
previous good copy in place.

  vaultwarden-db-backup.sh              dump, verify, publish
  vaultwarden-db-backup.sh --dry-run    report what would happen, change nothing
  vaultwarden-db-backup.sh --help       this text

Environment overrides (also honoured from the compose .env):
  SOURCE_DB, BACKUP_DIR, DEST_DB, SQLITE
USAGE
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    if (( DRY_RUN )); then
        echo "Source:      $SOURCE_DB"
        echo "Destination: $DEST_DB"
        echo "sqlite3:     $(command -v "$SQLITE" || echo 'NOT FOUND')"
        echo "Readable:    $([[ -r "$SOURCE_DB" ]] && echo yes || echo no)"
        echo "Would run:   $SQLITE <source> \".backup <destination>.tmp\", verify, then replace"
        exit 0
    fi

    if ! command -v "$SQLITE" >/dev/null 2>&1; then
        fail "Vaultwarden database backup: sqlite3 is missing" \
"$SQLITE is not installed on $(hostname), so no consistent database copy can be taken.

restic keeps backing up the hot vaultwarden-data/db.sqlite3, which can restore
into a torn write-ahead log.

Fix: apt install sqlite3"
    fi

    if [[ ! -r "$SOURCE_DB" ]]; then
        fail "Vaultwarden database backup: source unreadable" \
"$SOURCE_DB cannot be read on $(hostname).

Either Vaultwarden has moved its data directory or the path in
monitoring/vaultwarden-db-backup.sh is wrong. No consistent copy was taken."
    fi

    if ! mkdir -p "$BACKUP_DIR"; then
        fail "Vaultwarden database backup: cannot create the backup directory" \
"mkdir -p $BACKUP_DIR failed on $(hostname). No consistent copy was taken."
    fi

    # The vault contents in this file are encrypted, but the row structure and
    # every user's KDF parameters are not. Keep it away from other accounts.
    chmod 700 "$BACKUP_DIR"

    local tmp="$DEST_DB.tmp"
    rm -f "$tmp" "$tmp-wal" "$tmp-shm"

    # .backup is the online backup API, not a file copy. It reads through
    # SQLite, so the write-ahead log is folded in and the result is one
    # consistent file.
    if ! $SQLITE "$SOURCE_DB" ".backup '$tmp'" 2>&1; then
        rm -f "$tmp" "$tmp-wal" "$tmp-shm"
        fail "Vaultwarden database backup FAILED" \
"sqlite3 .backup of $SOURCE_DB failed on $(hostname).

The previous copy at $DEST_DB was left untouched, so it is now older than it
should be and tonight's restic snapshot has no fresh consistent database.

Check: ls -la $BACKUP_DIR; df -h /; docker logs vaultwarden"
    fi

    if ! verify "$tmp"; then
        rm -f "$tmp" "$tmp-wal" "$tmp-shm"
        fail "Vaultwarden database backup FAILED its integrity check" \
"The dump of $SOURCE_DB on $(hostname) was written, but PRAGMA integrity_check did
not return ok, so it was discarded.

The previous copy at $DEST_DB was left untouched. A failing integrity check on a
fresh dump points at the live database rather than at the copy.

Check: sqlite3 $SOURCE_DB 'PRAGMA integrity_check;'"
    fi

    chmod 600 "$tmp"

    # Rename last, so a reader never sees a half-written file and any failure
    # above leaves the previous verified copy in place.
    if ! mv -f "$tmp" "$DEST_DB"; then
        rm -f "$tmp"
        fail "Vaultwarden database backup: could not publish the dump" \
"mv $tmp $DEST_DB failed on $(hostname). The verified dump was discarded."
    fi

    log "Wrote verified Vaultwarden database copy to $DEST_DB ($(stat -c %s "$DEST_DB") bytes)"
}

main "$@"
