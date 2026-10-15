#!/usr/bin/env bash
#
# Create merch products in the live Shopware shop from a JSON data file.
#
# Each product is created once, with EN and DE name and description, price 0
# (the donation model, see docs/shopware/merch.md), a purchase price, weight
# and dimensions, the given categories, storefront visibility, and its images
# uploaded into the product media folder. The first image becomes the cover.
# New products start like the rest of the merch: active, stock 0 and closeout,
# so the storefront shows them as not available.
#
# The script is idempotent. A product whose number exists is skipped as a
# whole, and an image whose file name exists in the media library is reused
# rather than uploaded again. Image file names therefore have to be unique
# across the whole shop, which is why they carry a prefix such as
# sdwa5-print-model-.
#
# It writes to production, so it is **dry-run by default**. Claude Code's
# auto-mode classifier blocks production mutations unless the owner allows them.
#
# Usage:
#   tools/shopware/create-products.sh DATA.json              show what would be created
#   tools/shopware/create-products.sh DATA.json --apply      create it
#   tools/shopware/create-products.sh --help
#
# DATA.json holds the shop ids once (taxId, currencyId, salesChannelId,
# mediaFolderId, categoryIds, languages.en, languages.de) and a products array.
# Each product has productNumber, purchasePrice, weightKg, dimensionsMm
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
DATA=""
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
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
            price: [{currencyId: $c.currencyId, net: 0, gross: 0, linked: true}],
            purchasePrices: [{currencyId: $c.currencyId, net: $p.purchasePrice, gross: $p.purchasePrice, linked: true}],
            weight: $p.weightKg, width: $p.dimensionsMm.width, height: $p.dimensionsMm.height,
            length: $p.dimensionsMm.length,
            categories: ($c.categoryIds | map({id: .})),
            visibilities: [{salesChannelId: $c.salesChannelId, visibility: 30}],
            translations: {
                ($c.languages.en): {name: $p.name.en, description: $p.description.en},
                ($c.languages.de): {name: $p.name.de, description: $p.description.de}
            }
          }
        + (if ($pm | length) > 0 then {media: $pm, coverId: $pm[0].id} else {} end)'
}

CREATED=0; SKIPPED=0
COUNT="$(jq '.products | length' "$DATA")"
for (( i = 0; i < COUNT; i++ )); do
    P="$(jq -c ".products[$i]" "$DATA")"
    NUMBER="$(jq -r .productNumber <<<"$P")"

    EXISTING="$(sw_api POST /search/product "$(jq -cn --arg n "$NUMBER" \
        '{limit:1,filter:[{type:"equals",field:"productNumber",value:$n}]}')" | jq -r '.data[0].id // empty')"
    if [[ -n "$EXISTING" ]]; then
        sw_skip "$NUMBER exists ($EXISTING)"; SKIPPED=$((SKIPPED + 1)); continue
    fi

    MEDIA="[]"
    while IFS= read -r rel; do
        MID="$(media_for "$DIR/$rel")"
        printf '           image %s -> %s\n' "$rel" "$MID"
        MEDIA="$(jq -c --arg m "$MID" '. + [$m]' <<<"$MEDIA")"
    done < <(jq -r '.media[]' <<<"$P")

    PID="$(uuid)"
    if (( APPLY )); then
        sw_write_ok "$(sw_api POST /product "$(product_payload "$PID" "$P" "$MEDIA")")" "product $NUMBER"
    fi
    sw_report create "$NUMBER \"$(jq -r .name.en <<<"$P")\" ($PID), $(jq length <<<"$MEDIA") images, purchase price $(jq -r .purchasePrice <<<"$P")"
    CREATED=$((CREATED + 1))
done

if (( APPLY && CREATED )); then
    sw_write_ok "$(sw_api DELETE /_action/cache)" "cache clear"
fi
printf '%s %d, skipped %d\n' "$( (( APPLY )) && echo created || echo would create)" "$CREATED" "$SKIPPED"
