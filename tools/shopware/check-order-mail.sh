#!/usr/bin/env bash
#
# Render the live confirmation and cancellation templates without sending mail.
# Verify both languages and both formats against an existing order, then check
# payment branches and winter/summer timezone conversion with synthetic data.
# Requires the same API credentials as edit-slots.sh. No order is modified.
#
# Usage: tools/shopware/check-order-mail.sh ORDER_ID

set -euo pipefail
# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 1 && "$1" =~ ^[a-f0-9]{32}$ ]] || die "usage: $0 ORDER_ID"
order_id="$1"
edits="$(dirname "${BASH_SOURCE[0]}")/slot-edits/order-mail-copy.json"
sw_auth
order="$(sw_api POST /search/order "$(jq -nc --arg id "$order_id" \
    '{ids:[$id],includes:{order:["orderNumber","orderDateTime","salesChannelId","amountTotal"]}}')")"
jq -e '.data | length == 1' <<<"$order" >/dev/null || die "order not found"
number="$(jq -r '.data[0].orderNumber' <<<"$order")"
channel="$(jq -r '.data[0].salesChannelId' <<<"$order")"
expected_time="$(TZ=Europe/Vienna date -d "$(jq -r '.data[0].orderDateTime' <<<"$order")" +%H:%M)"

for lang in en de; do
    language="$(jq -r --arg lang "$lang" '.languages[$lang]' "$edits")"
    for kind in confirmation cancellation; do
        template="$(jq -r --arg kind "$kind" '.edits[] | select(.label | startswith($kind)) | .template' "$edits" | head -n 1)"
        body="$(jq -nc --arg tpl "$template" --arg order "$order_id" --arg channel "$channel" \
            '{mailTemplateId:$tpl,salesChannelId:$channel,entities:{order:$order,salesChannel:$channel},
              templateData:{timezone:"UTC",a11yDocuments:[]},strictRendering:true}')"
        rendered="$(sw_api POST /_action/mail-template/preview "$body" "sw-language-id: $language")"
        jq -e --arg time "$expected_time" '
            (.subject.type == "success" and .senderName.type == "success"
             and .contentHtml.type == "success" and .contentPlain.type == "success")
            and .senderName.content == "SdWa5"
            and ([.contentHtml.content,.contentPlain.content] | all(
                contains($time) and (contains("Storefront") | not)
                and (contains("Hallo Guten Tag") | not) and (contains("{{") | not)))
        ' <<<"$rendered" >/dev/null || die "$kind $lang failed rendering, branding or local time checks"
        if [[ "$kind" == cancellation ]]; then
            jq -e --arg n "$number" --arg lang "$lang" '.subject.content ==
                (if $lang == "de" then "Stornierung Ihrer Bestellung " else "Cancellation of your order " end) + $n' \
                <<<"$rendered" >/dev/null || die "$kind $lang has the wrong subject"
        elif jq -e '.data[0].amountTotal == 0' <<<"$order" >/dev/null; then
            jq -e '[.contentHtml.content,.contentPlain.content] | all(
                (contains("Sobald ein Zahlungseingang") | not)
                and (contains("As soon as your payment") | not)
                and (contains("nachträglich eine Zahlung") | not)
                and (contains("make additional payments") | not))' \
                <<<"$rendered" >/dev/null || die "$kind $lang demands payment for a free order"
        fi
        printf 'OK %s %s. HTML, plain text, sender, subject and local time checked.\n' "$kind" "$lang"
    done

    # The build endpoint renders supplied Twig without saving a template or
    # sending mail. It is available in the project's pinned Shopware 6.7.
    while IFS= read -r edit; do
        for total in 0 5; do
            body="$(jq -nc --argjson edit "$edit" --argjson total "$total" \
                '{mailTemplate:{contentHtml:$edit.new},mailTemplateType:{templateData:{order:{amountTotal:$total}}}}')"
            output="$(sw_api POST /_action/mail-template/build "$body" "sw-language-id: $language")"
            jq -e --argjson edit "$edit" --argjson total "$total" \
                'type == "string" and (if $total > 0 then . == $edit.old else contains($edit.old) | not end)' \
                <<<"$output" >/dev/null || die "$lang payment branch failed for total $total"
        done
    done < <(jq -c --arg lang "$lang" '.edits[] | select(.lang == $lang and (.label | contains("payment")))' "$edits")
    printf 'OK %s payment copy. Zero and positive totals checked in both formats.\n' "$lang"
done

for fixture in '2026-01-15T07:15:00+00:00 08:15' '2026-07-15T07:15:00+00:00 09:15'; do
    read -r input expected <<<"$fixture"
    body="$(jq -nc --arg input "$input" \
        --arg twig "{{ order.orderDateTime|format_datetime('medium', 'short', locale='de-DE', timezone='Europe/Vienna') }}" \
        '{mailTemplate:{contentHtml:$twig},mailTemplateType:{templateData:{timezone:"UTC",order:{orderDateTime:$input}}}}')"
    output="$(sw_api POST /_action/mail-template/build "$body")"
    jq -e --arg time "$expected" 'type == "string" and contains($time)' <<<"$output" >/dev/null \
        || die "Vienna timezone failed for $input"
done
printf 'OK Vienna local time. Winter and summer offsets checked. No mail sent.\n'
