#!/usr/bin/env bash
#
# Create merch products in the live Shopware shop from a JSON data file.
#
# Each product is created once, with EN and DE name and description, price 0
# (the donation model, see docs/shopware/merch.md), a purchase price, weight
# and dimensions, the given categories, storefront visibility, and its images
# uploaded into the product media folder. The first image becomes the cover.
# New products start like the rest of the merch: active, stock 0 and closeout,
# so the storefront shows them as not available. The purchase price is also
# written into the custom field sdwa5_production_cost, which the storefront
# shows as the production cost, see tools/shopware/sync-production-cost.sh.
#
# The script is idempotent. A product whose number exists is skipped as a
# whole, and an image whose file name exists in the media library is reused
# rather than uploaded again. Image file names therefore have to be unique
# across the whole shop, which is why they carry a prefix such as
# sdwa5-print-model-.
#
# --sync-media brings the images of a product that exists in line with the data
# file instead of skipping it. Missing images are added, every listed image gets
# its position from the list, and the first becomes the cover. Images the
# product has but the list does not name are left alone.
#
# It writes to production, so it is **dry-run by default**. Claude Code's
# auto-mode classifier blocks production mutations unless the owner allows them.
#
# Usage:
#   tools/shopware/create-products.sh DATA.json              show what would be created
#   tools/shopware/create-products.sh DATA.json --apply      create it
#   tools/shopware/create-products.sh DATA.json --sync-media [--apply]
#                                       also bring images of existing products in line
#   tools/shopware/create-products.sh --help
#
# DATA.json holds the shop ids once (taxId, currencyId, salesChannelId,
# mediaFolderId, categoryIds, languages.en, languages.de) and a products array.
# Each product has productNumber, purchasePrice, an optional listPrice (shown
# crossed out next to the price of 0), weightKg, dimensionsMm
# {width,height,length}, media (paths relative to the data file), and name and
# description keyed en and de. tools/shopware/products/print-models.json is
# the worked example.
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

set -euo pipefail

# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APPLY=0
SYNC_MEDIA=0
DATA=""
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --sync-media) SYNC_MEDIA=1 ;;
        -h|--help) sw_usage; exit 0 ;;
        -*) die "unknown option: ${arg}. Try --help." ;;
        *) [[ -z "$DATA" ]] || die "only one data file, got $DATA and $arg"; DATA="$arg" ;;
    esac
done
[[ -n "$DATA" ]] || die "no data file. Try --help."
[[ -r "$DATA" ]] || die "cannot read $DATA"
jq -e '.products | type == "array"' "$DATA" >/dev/null 2>&1 || die "$DATA has no products array"
DIR="$(cd "$(dirname "$DATA")" && pwd)"

# Every image has to exist before anything is written, so a typo cannot leave
# half a catalogue behind.
while IFS= read -r rel; do
    [[ -r "$DIR/$rel" ]] || die "missing image $DIR/$rel"
done < <(jq -r '.products[].media[]' "$DATA")

sw_auth
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'

uuid() { tr -d '-' < /proc/sys/kernel/random/uuid; }

FOLDER="$(jq -r .mediaFolderId "$DATA")"

# Prints the id of the media entity for FILE, uploading it first when no media
# with that file name exists. In a dry run a new file prints "new".
media_for() {
    local file="$1" base ext name id mime response
    base="$(basename "$file")"; ext="${base##*.}"; name="${base%.*}"
    id="$(sw_api POST /search/media "$(jq -cn --arg n "$name" --arg e "$ext" \
        '{limit:1,filter:[{type:"equals",field:"fileName",value:$n},{type:"equals",field:"fileExtension",value:$e}]}')" \
        | jq -r '.data[0].id // empty')"
    if [[ -n "$id" ]]; then printf '%s' "$id"; return; fi
    if (( ! APPLY )); then printf 'new'; return; fi

    case "$ext" in
        jpg|jpeg) mime=image/jpeg ;;
        png) mime=image/png ;;
        webp) mime=image/webp ;;
        *) die "unsupported image $base" ;;
    esac
    id="$(uuid)"
    sw_write_ok "$(sw_api POST /media "$(jq -cn --arg i "$id" --arg f "$FOLDER" '{id:$i,mediaFolderId:$f}')")" "media $base"
    # sw_api sends text bodies only, so the binary upload calls curl itself.
    response="$(curl -s --max-time 120 -X POST \
        "$SW_API_URL/api/_action/media/$id/upload?extension=$ext&fileName=$(jq -rn --arg n "$name" '$n|@uri')" \
        -H "Authorization: Bearer $SW_TOKEN" -H "Content-Type: $mime" -H 'Accept: application/json' \
        --data-binary "@$file")"
    sw_write_ok "$response" "upload $base"
    printf '%s' "$id"
}

# product_payload PRODUCT_ID PRODUCT_JSON MEDIA_IDS_JSON prints the create body.
# Product media rows get ids derived from the product id, so the cover can be
# named in the same request.
product_payload() {
    jq -cn --arg pid "$1" --argjson p "$2" --argjson media "$3" --slurpfile c "$DATA" '
        $c[0] as $c
        | ($media | to_entries
            | map({id: (($pid | .[0:24]) + (("00000000" + (.key | tostring)) | .[-8:])), mediaId: .value, position: .key})) as $pm
        | {
            id: $pid, productNumber: $p.productNumber, active: true, stock: 0, isCloseout: true,
            taxId: $c.taxId,
            price: [{currencyId: $c.currencyId, net: 0, gross: 0, linked: true}
                + (if $p.listPrice then {listPrice: {currencyId: $c.currencyId, net: $p.listPrice,
                    gross: $p.listPrice, linked: true}} else {} end)],
            purchasePrices: [{currencyId: $c.currencyId, net: $p.purchasePrice, gross: $p.purchasePrice, linked: true}],
            weight: $p.weightKg, width: $p.dimensionsMm.width, height: $p.dimensionsMm.height,
            length: $p.dimensionsMm.length,
            categories: ($c.categoryIds | map({id: .})),
            visibilities: [{salesChannelId: $c.salesChannelId, visibility: 30}],
            translations: {
                ($c.languages.en): {name: $p.name.en, description: $p.description.en,
                    customFields: {sdwa5_production_cost: $p.purchasePrice}},
                ($c.languages.de): {name: $p.name.de, description: $p.description.de,
                    customFields: {sdwa5_production_cost: $p.purchasePrice}}
            }
          }
        + (if ($pm | length) > 0 then {media: $pm, coverId: $pm[0].id} else {} end)'
}

# sync_media PRODUCT_ID PRODUCT_JSON MEDIA_IDS_JSON brings the product's image
# rows in line with MEDIA_IDS_JSON. A row that holds a listed image keeps its id,
# so nothing is removed and re-added. Prints "current" when nothing changes.
sync_media() {
    local pid="$1" p="$2" media="$3" product body
    product="$(sw_api POST /search/product "$(jq -cn --arg i "$pid" \
        '{ids:[$i],associations:{media:{}}}')" | jq -c '.data[0] // {}')"
    body="$(jq -cn --argjson have "$product" --argjson want "$media" '
        ($have.media // []) as $rows
        | [$want | to_entries[] | .key as $k | .value as $m
            | {id: (([$rows[] | select(.mediaId == $m) | .id] | first) // null), mediaId: $m, position: $k}]
        | {media: ., coverId: .[0].id, current: (all(.id != null) and
            ([.[] | .id as $i | .position as $pos | $rows[] | select(.id == $i) | .position == $pos] | all)
            and $have.coverId == .[0].id)}')"
    if [[ "$(jq -r .current <<<"$body")" == true ]]; then printf 'current'; return; fi
    (( APPLY )) || { printf 'change'; return; }
    body="$(jq -c '.media |= map(.id //= "new")' <<<"$body")"
    local rows="[]" r id
    while IFS= read -r r; do
        id="$(jq -r .id <<<"$r")"; [[ "$id" == new ]] && id="$(uuid)"
        rows="$(jq -c --argjson r "$r" --arg i "$id" '. + [$r + {id: $i}]' <<<"$rows")"
    done < <(jq -c '.media[]' <<<"$body")
    sw_write_ok "$(sw_api PATCH "/product/$pid" "$(jq -cn --argjson m "$rows" '{media: $m, coverId: $m[0].id}')")" \
        "images of $(jq -r .productNumber <<<"$p")"
    printf 'changed'
}

images_of() {
    local rel mid ids="[]"
    while IFS= read -r rel; do
        mid="$(media_for "$DIR/$rel")"
        printf '           image %s -> %s\n' "$rel" "$mid" >&2
        ids="$(jq -c --arg m "$mid" '. + [$m]' <<<"$ids")"
    done < <(jq -r '.media[]' <<<"$1")
    printf '%s' "$ids"
}

CREATED=0; SKIPPED=0; SYNCED=0
COUNT="$(jq '.products | length' "$DATA")"
for (( i = 0; i < COUNT; i++ )); do
    P="$(jq -c ".products[$i]" "$DATA")"
    NUMBER="$(jq -r .productNumber <<<"$P")"

    EXISTING="$(sw_api POST /search/product "$(jq -cn --arg n "$NUMBER" \
        '{limit:1,filter:[{type:"equals",field:"productNumber",value:$n}]}')" | jq -r '.data[0].id // empty')"
    if [[ -n "$EXISTING" ]] && (( SYNC_MEDIA )); then
        STATE="$(sync_media "$EXISTING" "$P" "$(images_of "$P")")"
        if [[ "$STATE" == current ]]; then
            sw_skip "$NUMBER images already current"; SKIPPED=$((SKIPPED + 1))
        else
            sw_report images "$NUMBER images set to the $(jq '.media | length' <<<"$P") listed, the first as cover"
            SYNCED=$((SYNCED + 1))
        fi
        continue
    fi
    if [[ -n "$EXISTING" ]]; then
        sw_skip "$NUMBER exists ($EXISTING)"; SKIPPED=$((SKIPPED + 1)); continue
    fi

    MEDIA="$(images_of "$P")"

    PID="$(uuid)"
    if (( APPLY )); then
        sw_write_ok "$(sw_api POST /product "$(product_payload "$PID" "$P" "$MEDIA")")" "product $NUMBER"
    fi
    sw_report create "$NUMBER \"$(jq -r .name.en <<<"$P")\" ($PID), $(jq length <<<"$MEDIA") images, purchase price $(jq -r .purchasePrice <<<"$P")"
    CREATED=$((CREATED + 1))
done

if (( APPLY && (CREATED || SYNCED) )); then
    sw_write_ok "$(sw_api DELETE /_action/cache)" "cache clear"
fi
printf '%s %d, skipped %d\n' "$( (( APPLY )) && echo created || echo would create)" "$CREATED" "$SKIPPED"
(( SYNC_MEDIA )) && printf '%s images of %d\n' "$( (( APPLY )) && echo synced || echo would sync)" "$SYNCED"
exit 0
