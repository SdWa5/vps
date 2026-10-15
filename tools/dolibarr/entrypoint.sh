#!/usr/bin/env bash
# Dolibarr 23.0.4 ships three inline SQL comments without the whitespace that
# core/lib/admin.lib.php::run_sql requires before it removes inline comments.
# On MariaDB 12.3 the joined CREATE statements fail near "--ip used ...".
# Normalize only those comments, then retain the official startup procedure.
# Remove this version-specific wrapper after verifying a corrected upstream image.

set -euo pipefail

normalize_sql_comments() {
    local root="$1" file original corrected
    local -a files=(llx_don-don.sql llx_opensurvey_comments-opensurvey.sql llx_opensurvey_user_studs-opensurvey.sql)
    for file in "${files[@]}"; do
        [[ -f "$root/$file" ]] || { printf 'Missing expected SQL definition: %s\n' "$file" >&2; return 1; }
        original="$(grep -Fc -- '--ip used to create record (for public submission page)' "$root/$file" || true)"
        corrected="$(grep -Fc -- '-- ip used to create record (for public submission page)' "$root/$file" || true)"
        [[ "$original" == 1 && "$corrected" == 0 || "$original" == 0 && "$corrected" == 1 ]] || {
            printf 'Unexpected SQL definition; refusing to normalize %s.\n' "$file" >&2
            return 1
        }
    done
    for file in "${files[@]}"; do
        sed -i 's/--ip used to create record (for public submission page)/-- ip used to create record (for public submission page)/' "$root/$file"
    done
}

main() {
    [[ "${DOLI_VERSION:-}" == 23.0.4 ]] || {
        printf 'The SQL normalization wrapper requires Dolibarr 23.0.4.\n' >&2
        return 1
    }
    normalize_sql_comments /var/www/html/install/mysql/tables
    exec /usr/local/bin/docker-run.sh "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
