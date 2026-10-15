#!/usr/bin/env bats
# Tests for tools/shopware/edit-slots.sh

load test_helper

setup() {
    common_setup
    sw_setup
    # Two slots, the first in two languages. Each config carries a second key,
    # which a write has to keep.
    jq -n '{total: 3, data: [
        {cmsSlotId: "slot1", languageId: "lang-de", config: {content: {source: "static",
            value: "<tr><td>L2122</td><td>2-Wege</td></tr><tr><td>SKRAM</td><td>2</td></tr>"}, verticalAlign: {value: null}}},
        {cmsSlotId: "slot1", languageId: "lang-en", config: {content: {source: "static",
            value: "<tr><td>L2122</td><td>2-way</td></tr><tr><td>SKRAM</td><td>2</td></tr>"}, verticalAlign: {value: null}}},
        {cmsSlotId: "slot2", languageId: "lang-en", config: {content: {source: "static",
            value: "<td>HF</td><td>250</td>"}, verticalAlign: {value: null}}}
    ]}' > "$STUB_SW_DIR/_api_search_cms-slot-translation"
    EDITS="$BATS_TEST_TMPDIR/edits.json"
    jq -n '{languages: {de: "lang-de", en: "lang-en"}, edits: [
        {label: "model de", slot: "slot1", lang: "de", old: "<td>2-Wege</td>", new: "<td>3-Wege</td>"},
        {label: "skram de", slot: "slot1", lang: "de", old: "<td>SKRAM</td><td>2</td>", new: "<td>SKRAM</td><td>2 (6 geplant)</td>"},
        {label: "model en", slot: "slot1", lang: "en", old: "<td>2-way</td>", new: "<td>3-way</td>"},
        {label: "power en", slot: "slot2", lang: "lang-en", old: "<td>250</td>", new: "<td>360</td>"}
    ]}' > "$EDITS"
}

edit_slots() {
    run "$REPO_ROOT/tools/shopware/edit-slots.sh" "$@"
}

count() {
    grep -c "$1" "$STUB_SW_LOG" || true
}

# The body of the PATCH sent to one slot; the n-th one when a slot gets several.
patch_body() {
    grep "^PATCH /api/cms-slot/$1 " "$STUB_SW_LOG" | sed -n "${2:-1}p" | sed "s|^PATCH /api/cms-slot/$1 ||"
}

@test "help needs no credentials and names the switch" {
    unset SW_API_URL
    export SHOPWARE_MCP_CONFIG=/nonexistent
    edit_slots --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"slot-edits"* ]]
}

@test "an unknown option is rejected" {
    edit_slots "$EDITS" --frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a missing edits file explains itself" {
    edit_slots
    [ "$status" -ne 0 ]
    [[ "$output" == *"no edits file"* ]]
}

@test "an edit without old text stops the run before any request" {
    jq '.edits[0].old = ""' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty old"* ]]
    [ ! -s "$STUB_SW_LOG" ]
}

@test "a dry run reports every edit and writes nothing" {
    edit_slots "$EDITS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"would    model de"* ]]
    [[ "$output" == *"would    power en"* ]]
    [[ "$output" == *"4 to change, 0 already current."* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

@test "the search asks for the live version of each slot once" {
    edit_slots "$EDITS"
    body="$(grep '^POST /api/search/cms-slot-translation ' "$STUB_SW_LOG" | sed 's|^POST /api/search/cms-slot-translation ||')"
    [ "$(jq -c '.filter[0].value' <<<"$body")" = '["slot1","slot2"]' ]
    [ "$(jq -r '.filter[1].value' <<<"$body")" = "0fa91ce3e96a4bc2be4bd9ce752c3425" ]
}

@test "apply writes one request per slot and language, with every edit and the other config keys" {
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"4 changed, 0 already current."* ]]
    [ "$(count '^PATCH /api/cms-slot/slot1 ')" -eq 2 ]
    [ "$(count '^PATCH /api/cms-slot/slot2 ')" -eq 1 ]
    [ "$(jq -r .config.content.value <<<"$(patch_body slot1 1)")" = "<tr><td>L2122</td><td>3-Wege</td></tr><tr><td>SKRAM</td><td>2 (6 geplant)</td></tr>" ]
    [ "$(jq -r .config.content.value <<<"$(patch_body slot1 2)")" = "<tr><td>L2122</td><td>3-way</td></tr><tr><td>SKRAM</td><td>2</td></tr>" ]
    [ "$(jq -c .config.verticalAlign <<<"$(patch_body slot2)")" = '{"value":null}' ]
    [ "$(count '^DELETE /api/_action/cache')" -eq 1 ]
}

@test "an edit that is already in place is skipped, and nothing is written" {
    jq '.edits = [{label: "power en", slot: "slot2", lang: "en", old: "<td>999</td>", new: "<td>250</td>"}]' \
        "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip     power en, already current"* ]]
    [[ "$output" == *"0 changed, 1 already current."* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

@test "old text found twice stops the run, and the edits before it are not written either" {
    jq '.edits += [{label: "ambiguous", slot: "slot1", lang: "en", old: "<td>", new: "<p>"}]' \
        "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"ambiguous: old text found"*"expected once"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "old text that is missing, with the new text absent too, stops the run" {
    jq '.edits[3].old = "<td>777</td>"' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"power en: old text found 0 times"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "a language the slot has no translation in stops the run" {
    jq '.edits[3].lang = "de"' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"slot slot2 has no translation in language lang-de"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "a refused token stops the run before it reads" {
    export STUB_SW_NO_TOKEN=1
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"access token"* ]]
    [ "$(count '^POST /api/search')" -eq 0 ]
}

# A mail template with an HTML and a plain field in one language, and an
# insertion edit into each that keeps its anchor.
mail_setup() {
    jq -n '{total: 1, data: [{mailTemplateId: "tpl1", languageId: "lang-en",
        contentHtml: "<p>Hi</p><strong>Your order:</strong>", contentPlain: "Hi\n\nYour order:"}]}' \
        > "$STUB_SW_DIR/_api_search_mail-template-translation"
    jq '.edits = [
        {label: "mail html", target: "mail-template", template: "tpl1", field: "contentHtml", lang: "en",
         old: "<strong>Your order:</strong>", new: "<p>Donate.</p><strong>Your order:</strong>"},
        {label: "mail plain", target: "mail-template", template: "tpl1", field: "contentPlain", lang: "en",
         old: "Your order:", new: "Donate.\n\nYour order:"}]' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
}

@test "a mail template edit writes both fields in one request, under the edit's language" {
    mail_setup
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 changed, 0 already current."* ]]
    [ "$(count '^POST /api/search/cms-slot-translation')" -eq 0 ]
    [ "$(jq -c '.filter[0].value' <<<"$(grep '^POST /api/search/mail-template-translation ' "$STUB_SW_LOG" \
        | sed 's|^POST /api/search/mail-template-translation ||')")" = '["tpl1"]' ]
    [ "$(count '^PATCH /api/mail-template/tpl1 ')" -eq 1 ]
    body="$(grep '^PATCH /api/mail-template/tpl1 ' "$STUB_SW_LOG" | sed 's|^PATCH /api/mail-template/tpl1 ||')"
    [ "$(jq -r .contentHtml <<<"$body")" = "<p>Hi</p><p>Donate.</p><strong>Your order:</strong>" ]
    [ "$(jq -r .contentPlain <<<"$body")" = "$(printf 'Hi\n\nDonate.\n\nYour order:')" ]
    [ "$(count '^DELETE /api/_action/cache')" -eq 1 ]
}

@test "an insertion that is already in place is skipped, although its anchor is still there" {
    mail_setup
    jq '.data[0].contentHtml = "<p>Hi</p><p>Donate.</p><strong>Your order:</strong>"
        | .data[0].contentPlain = "Hi\n\nDonate.\n\nYour order:"' "$STUB_SW_DIR/_api_search_mail-template-translation" \
        > "$STUB_SW_DIR/m" && mv "$STUB_SW_DIR/m" "$STUB_SW_DIR/_api_search_mail-template-translation"
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 changed, 2 already current."* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "a mail template edit with an unknown field stops the run before any request" {
    mail_setup
    jq '.edits[0].field = "description"' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"subject or senderName"* ]]
    [ ! -s "$STUB_SW_LOG" ]
}

@test "a template without the edit's language stops the run" {
    mail_setup
    jq '.edits[1].lang = "de"' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"mail template tpl1 has no translation in language lang-de"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "the shipped edits name a label, a known language and both texts" {
    for f in "$REPO_ROOT"/tools/shopware/slot-edits/*.json; do
        run jq -e '(.languages | keys) as $l
            | .edits | length > 0 and all(.label and (.slot or (.template and .field))
                and (.lang as $x | $l | index($x)) and .old and .new)' "$f"
        [ "$status" -eq 0 ] || { echo "$f"; false; }
    done
}

@test "the order mail insertions keep their anchors and only show for donation items" {
    f="$REPO_ROOT/tools/shopware/slot-edits/order-mail-donation.json"
    run jq -e '.edits | length == 4
        and all(. as $e | $e.new | endswith($e.old))
        and all(.new | contains("unitPrice == 0") and contains("listPrice") and contains("{% endif %}"))' "$f"
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.edits[].field] | sort | join(" ")' "$f")" = "contentHtml contentHtml contentPlain contentPlain" ]
}

@test "mail subjects and senders are edited together without changing either body" {
    mail_setup
    jq '.data[0] += {subject: "New document", senderName: "Storefront"}' \
        "$STUB_SW_DIR/_api_search_mail-template-translation" > "$STUB_SW_DIR/m"
    mv "$STUB_SW_DIR/m" "$STUB_SW_DIR/_api_search_mail-template-translation"
    jq '.edits = [
        {label: "subject", target: "mail-template", template: "tpl1", field: "subject", lang: "en",
         old: "New document", new: "Order cancelled"},
        {label: "sender", target: "mail-template", template: "tpl1", field: "senderName", lang: "en",
         old: "Storefront", new: "SdWa5"}
    ]' "$EDITS" > "$EDITS.new" && mv "$EDITS.new" "$EDITS"
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [ "$(count '^PATCH /api/mail-template/tpl1 ')" -eq 1 ]
    body="$(grep '^PATCH /api/mail-template/tpl1 ' "$STUB_SW_LOG" | sed 's|^PATCH /api/mail-template/tpl1 ||')"
    [ "$(jq -r .subject <<<"$body")" = "Order cancelled" ]
    [ "$(jq -r .senderName <<<"$body")" = "SdWa5" ]
    [ "$(jq -r .contentHtml <<<"$body")" = "<p>Hi</p><strong>Your order:</strong>" ]
    [ "$(jq -r .contentPlain <<<"$body")" = "$(printf 'Hi\n\nYour order:')" ]

    jq --argjson body "$body" '.data[0] += $body' "$STUB_SW_DIR/_api_search_mail-template-translation" \
        > "$STUB_SW_DIR/m" && mv "$STUB_SW_DIR/m" "$STUB_SW_DIR/_api_search_mail-template-translation"
    : > "$STUB_SW_LOG"
    edit_slots "$EDITS" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 changed, 2 already current."* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}
