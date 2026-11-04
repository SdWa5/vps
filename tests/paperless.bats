#!/usr/bin/env bats

setup() {
    export TOOLS="$BATS_TEST_DIRNAME/../tools/paperless"
    export SDWA5_PAPERLESS_DEV_DIR="$BATS_TEST_TMPDIR/dev"
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export SPEC="$BATS_TEST_TMPDIR/spec.json"
    jq --arg d "$BATS_TEST_TMPDIR/passwords" '.password_dir = $d' "$TOOLS/paperless-spec.example.json" > "$SPEC"
}

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
    chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

@test "dev-instance: without a command it prints the usage and does nothing" {
    stub docker 'exit 97'
    run bash "$TOOLS/dev-instance.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *'dev mirror of paper.sdwa5.org'* ]]
}

@test "dev-instance: an unknown instance is refused before docker runs" {
    stub docker 'exit 97'
    run bash "$TOOLS/dev-instance.sh" up shared
    [ "$status" -ne 0 ]
    [[ "$output" == *'Use sdwa5 or home'* ]]
}

@test "dev-instance: the images follow the production compose file, anchors skipped" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; compose_image paperless_sdwa5; printf " "; compose_image paperless_sdwa5_broker; printf " "; compose_image paperless_sdwa5_db'
    [ "$status" -eq 0 ]
    [[ "$output" == "ghcr.io/paperless-ngx/paperless-ngx:"*"@sha256:"*" valkey/valkey:"*" mariadb:"* ]]
}

@test "dev-instance: the shared settings come from x-paperless-env" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; compose_paperless_env'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PAPERLESS_CONSUMER_DISABLE=true'* ]]
    [[ "$output" == *'PAPERLESS_TASK_WORKERS=1'* ]]
    [[ "$output" != *'PAPERLESS_URL'* ]]
}

@test "dev-instance: the generated secrets are private and never printed" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; select_instance home; ensure_secrets'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(stat -c %a "$SDWA5_PAPERLESS_DEV_DIR/home/app.env")" = 600 ]
    [ "$(stat -c %a "$SDWA5_PAPERLESS_DEV_DIR/home/passwords/admin")" = 600 ]
    grep -q '^PAPERLESS_ADMIN_PASSWORD=[0-9a-f]\{32\}$' "$SDWA5_PAPERLESS_DEV_DIR/home/app.env"
}

@test "setup: without a spec it prints the usage" {
    run bash "$TOOLS/setup.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *'dry-run by default'* ]]
}

@test "setup: a spec without password_dir is refused" {
    jq 'del(.password_dir)' "$SPEC" > "$BATS_TEST_TMPDIR/bad.json"
    stub curl 'exit 97'
    run bash "$TOOLS/setup.sh" "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'no password_dir'* ]]
}

@test "setup: a workflow read back from the API matches the wanted one" {
    run bash -c 'source "$TOOLS/setup.sh"
        wanted="$(share_workflow "Share tag Shared with group members" 3 2 | normalise_workflow)"
        api="{\"id\":7,\"name\":\"Share tag Shared with group members\",\"order\":0,\"enabled\":true,
            \"triggers\":[{\"id\":2,\"type\":3,\"sources\":[\"4\",\"3\",\"2\",\"1\"],\"matching_algorithm\":0,\"filter_has_tags\":[3],\"filter_path\":null},
                          {\"id\":1,\"type\":2,\"sources\":[1,2,3,4],\"matching_algorithm\":0,\"filter_has_tags\":[3]}],
            \"actions\":[{\"id\":1,\"type\":1,\"assign_view_groups\":[2],\"assign_change_groups\":[2],\"assign_tags\":[]}]}"
        [ "$(normalise_workflow <<< "$api")" = "$wanted" ]'
    [ "$status" -eq 0 ]
}

@test "setup: a workflow that lost Web UI uploads differs" {
    run bash -c 'source "$TOOLS/setup.sh"
        wanted="$(share_workflow "w" 3 2 | normalise_workflow)"
        changed="$(share_workflow "w" 3 2 | jq -c ".triggers[0].sources = [1, 2, 3]" | normalise_workflow)"
        [ "$changed" != "$wanted" ]'
    [ "$status" -eq 0 ]
}

@test "lib: a cached token is used without asking /api/token/, and only on a pipe" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'cached-token' > "$BATS_TEST_TMPDIR/passwords/alice.token"
    stub curl 'case "$*" in *api/token*) exit 97 ;; esac
for arg; do [ "$arg" = cached-token ] && exit 98; done
while [ $# -gt 0 ]; do [ "$1" = --config ] && cat "$2"; shift; done'
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; curl_as alice "$PAPERLESS_URL/api/"'
    [ "$status" -eq 0 ]
    [ "$output" = 'header = "Authorization: Token cached-token"' ]
}

@test "lib: a throttled token request waits and retries" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'pw' > "$BATS_TEST_TMPDIR/passwords/bob"
    stub sleep 'exit 0'
    stub curl "cat >/dev/null
if [ -e '$BATS_TEST_TMPDIR/once' ]; then printf '{\"token\":\"fresh\"}'; else touch '$BATS_TEST_TMPDIR/once'; printf '{\"detail\":\"Request was throttled. Expected available in 3 seconds.\"}'; fi"
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; ensure_token bob'
    [ "$status" -eq 0 ]
    [[ "$output" == *'waiting 3 s'* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/passwords/bob.token")" = fresh ]
}

@test "lib: a wrong password fails without a token file" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'pw' > "$BATS_TEST_TMPDIR/passwords/bob"
    stub curl 'cat >/dev/null; printf "{\"non_field_errors\":[\"Unable to log in\"]}"'
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; ensure_token bob'
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/passwords/bob.token" ]
}

@test "visibility-check: the generated PDF has a valid cross-reference offset" {
    run bash -c 'source "$TOOLS/visibility-check.sh"; make_pdf "visibility-check abc alice private" "$BATS_TEST_TMPDIR/t.pdf"'
    [ "$status" -eq 0 ]
    offset="$(tail -n 2 "$BATS_TEST_TMPDIR/t.pdf" | head -n 1)"
    [ "$(tail -c +"$((offset + 1))" "$BATS_TEST_TMPDIR/t.pdf" | head -n 1)" = xref ]
    head -c 8 "$BATS_TEST_TMPDIR/t.pdf" | grep -q '^%PDF-1.4'
}

@test "visibility-check: group membership is read from the spec" {
    run bash -c 'source "$TOOLS/visibility-check.sh"; in_group alice members && ! in_group alice board'
    [ "$status" -eq 0 ]
}

@test "setup: a share without a tag triggers on every added document" {
    run bash -c 'source "$TOOLS/setup.sh"; share_workflow "Share all documents with group board" null 2'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.triggers[] | {type, filter_has_tags}]' <<< "$output")" = '[{"type":2,"filter_has_tags":[]}]' ]
}

@test "visibility-check: a share without a tag shows every document to the group only" {
    jq '.shares += [{"group": "members"}] | .users += [{"username": "carol", "groups": []}]' "$SPEC" > "$BATS_TEST_TMPDIR/all.json"
    run bash -c 'SPEC="$BATS_TEST_TMPDIR/all.json"; source "$TOOLS/visibility-check.sh"; SPEC="$BATS_TEST_TMPDIR/all.json"
        shared_with_all alice && shared_with_all bob && ! shared_with_all carol'
    [ "$status" -eq 0 ]
}

# A fake Paperless for upload-tree.sh. Every request is logged as
# "METHOD URL|form field|...". Hashes listed in held/ exist, task.json is the
# task answer, and new tags count up from 101.
paperless_stub() {
    mkdir -p "$BATS_TEST_TMPDIR/passwords" "$BATS_TEST_TMPDIR/held"
    printf 'stefan-token' > "$BATS_TEST_TMPDIR/passwords/stefan.token"
    printf '{"results":[{"status":"success","related_document_ids":[42]}]}' > "$BATS_TEST_TMPDIR/task.json"
    printf '{"results":[{"id":5,"name":"Finanzen"}],"next":null}' > "$BATS_TEST_TMPDIR/tags.json"
    stub sleep 'exit 0'
    stub file 'for a; do p="$a"; done
case "$p" in *.pdf) echo application/pdf ;; *.jpg) echo image/jpeg ;; *.png) echo image/png ;; *) echo text/plain ;; esac'
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<STUB
#!/bin/sh
d='$BATS_TEST_TMPDIR'
method=GET; out=; form=
for a; do url="\$a"; done
while [ \$# -gt 0 ]; do
    case "\$1" in
        --output) out="\$2"; shift ;;
        --request) method="\$2"; shift ;;
        -F|--form-string) form="\$form|\$2"; shift ;;
        --max-time|--config|--header|--data-binary|--write-out) shift ;;
    esac
    shift
done
printf '%s %s%s\n' "\$method" "\$url" "\$form" >> "\$d/requests"
case "\$method \$url" in
    "GET "*/api/tags/*) body="\$(cat "\$d/tags.json")" ;;
    "GET "*checksum__iexact=*)
        sha="\${url#*checksum__iexact=}"; sha="\${sha%%&*}"
        if [ -e "\$d/held/\$sha" ]; then body='{"count":1,"results":[{"id":7}]}'; else body='{"count":0,"results":[]}'; fi ;;
    "POST "*/api/tags/) n=\$(( \$(cat "\$d/tagn" 2>/dev/null || echo 100) + 1 )); echo \$n > "\$d/tagn"; body="{\"id\":\$n}" ;;
    "POST "*/post_document/) body='"task-1"' ;;
    "GET "*/api/tasks/*) body="\$(cat "\$d/task.json")" ;;
esac
printf '%s' "\$body" > "\$out"
printf 200
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT"
}

# put RELATIVE_PATH writes a file with its own path as content, so every file
# has its own hash.
put() { mkdir -p "$ROOT/$(dirname "$1")"; printf '%s' "$1" > "$ROOT/$1"; }

upload_tree() { bash "$TOOLS/upload-tree.sh" "$@" 2>"$BATS_TEST_TMPDIR/err"; }

@test "upload-tree: junk, secrets, unsafe names and other types are skipped with a reason" {
    paperless_stub
    put 'a/Thumbs.db'; put 'a/~$brief.docx'; put 'a/.~lock.brief.odt#'; put 'a/x.sync-conflict-1.pdf'
    put 'a/konto_sensibel.pdf'; put 'a/say "hi".pdf'; put 'a/notes.txt'
    run upload_tree "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cut -f2 "$BATS_TEST_TMPDIR/err" | sort | paste -sd' ')" = 'junk junk junk junk local:text/plain name secret' ]
    ! grep -q checksum "$BATS_TEST_TMPDIR/requests"
}

@test "upload-tree: a dated name gives title, created and the folder tags plus Offen" {
    paperless_stub
    put 'Finanzen/Strom/2024-03-01_Rechnung_Strom_OFFEN.pdf'
    run upload_tree "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    line="$(grep '^would-upload' <<< "$output")"
    [ "$(cut -f3- <<< "$line")" = "$ROOT/Finanzen/Strom/2024-03-01_Rechnung_Strom_OFFEN.pdf"$'\tRechnung Strom\t2024-03-01\tFinanzen/Strom/Offen' ]
    [ "$(grep -c '^would-create-tag' <<< "$output")" -eq 2 ]
}

@test "upload-tree: other names stay verbatim, a bad date is no date, long titles are cut" {
    paperless_stub
    long="$(printf 'x%.0s' {1..200})"
    put 'Tickets/Ozora/Böhm, Verena/Rechnung Nr. 5.pdf'; put '2024-13-45_x.pdf'; put "$long.pdf"
    run upload_tree "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    grep -qF $'\tRechnung Nr. 5\t\tTickets/Ozora/Böhm, Verena' <<< "$output"
    grep -qF $'\t2024-13-45_x\t\t' <<< "$output"
    [ "$(grep -F "$long" <<< "$output" | cut -f4 | tr -d '\n' | wc -c)" -eq 128 ]
}

@test "upload-tree: a dry-run writes nothing, names a tag once and reports a second copy" {
    paperless_stub
    put 'Bildung/a.pdf'; put 'Bildung/b.pdf'; printf 'Bildung/a.pdf' > "$ROOT/Bildung/c.pdf"
    run upload_tree "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    ! grep -q '^POST' "$BATS_TEST_TMPDIR/requests"
    [ "$(grep -c '^would-create-tag	Bildung$' <<< "$output")" -eq 1 ]
    [ "$(grep -c '^would-upload' <<< "$output")" -eq 2 ]
    grep -q "^skip	duplicate	$ROOT/Bildung/c.pdf\$" "$BATS_TEST_TMPDIR/err"
}

@test "upload-tree: a held checksum prints exists and is not uploaded" {
    paperless_stub
    put 'Finanzen/a.pdf'
    sha="$(sha256sum < "$ROOT/Finanzen/a.pdf" | cut -d' ' -f1)"
    touch "$BATS_TEST_TMPDIR/held/$sha"
    run upload_tree --apply "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "exists	7	$sha	$ROOT/Finanzen/a.pdf" ]
    ! grep -q '^POST' "$BATS_TEST_TMPDIR/requests"
}

@test "upload-tree: --apply creates the tag, posts the fields, waits and stops at --limit" {
    paperless_stub
    put 'Finanzen/Strom/2024-03-01_Rechnung.pdf'; put 'Finanzen/Strom/2024-04-01_Rechnung.pdf'
    run upload_tree --apply --limit 1 "$SPEC" stefan "$ROOT"
    [ "$status" -eq 0 ]
    sha="$(sha256sum < "$ROOT/Finanzen/Strom/2024-03-01_Rechnung.pdf" | cut -d' ' -f1)"
    [ "$output" = "tag	101	Strom"$'\n'"uploaded	42	$sha	$ROOT/Finanzen/Strom/2024-03-01_Rechnung.pdf" ]
    grep -qF "/api/documents/post_document/|document=@\"$ROOT/Finanzen/Strom/2024-03-01_Rechnung.pdf\"|title=Rechnung|created=2024-03-01|tags=5|tags=101" "$BATS_TEST_TMPDIR/requests"
    grep -q 'tasks/?task_id=task-1' "$BATS_TEST_TMPDIR/requests"
    [ "$(grep -c 'post_document' "$BATS_TEST_TMPDIR/requests")" -eq 1 ]
}

@test "upload-tree: a failed task stops the run with its message" {
    paperless_stub
    put 'a.pdf'
    printf '{"results":[{"status":"failure","result_data":"broken PDF"}]}' > "$BATS_TEST_TMPDIR/task.json"
    run upload_tree --apply "$SPEC" stefan "$ROOT"
    [ "$status" -ne 0 ]
    grep -q 'failed: "broken PDF"' "$BATS_TEST_TMPDIR/err"
    ! grep -q '^uploaded' <<< "$output"
}
