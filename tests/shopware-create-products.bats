#!/usr/bin/env bats
# Tests for tools/shopware/create-products.sh

load test_helper

setup() {
    common_setup
    sw_setup
    DATA_DIR="$BATS_TEST_TMPDIR/products"
    mkdir -p "$DATA_DIR/media"
    printf 'jpg-a' > "$DATA_DIR/media/ex-a.jpg"
    printf 'jpg-b' > "$DATA_DIR/media/ex-b.jpg"
    printf 'png-c' > "$DATA_DIR/media/ex-c.png"
    jq -n '{
        taxId: "tax1", currencyId: "eur1", salesChannelId: "sc1", mediaFolderId: "folder1",
        categoryIds: ["cat1", "cat2"], languages: {en: "lang-en", de: "lang-de"},
        products: [
          {productNumber: "EX-1", purchasePrice: 1.75, weightKg: 0.033,
           dimensionsMm: {width: 41, height: 80, length: 43}, media: ["media/ex-a.jpg", "media/ex-b.jpg"],
           name: {en: "Example One", de: "Beispiel Eins"}, description: {en: "<p>one</p>", de: "<p>eins</p>"}},
          {productNumber: "EX-2", purchasePrice: 2.77, weightKg: 0.056,
           dimensionsMm: {width: 52, height: 77, length: 68}, media: ["media/ex-c.png"],
           name: {en: "Example Two", de: "Beispiel Zwei"}, description: {en: "<p>two</p>", de: "<p>zwei</p>"}}
        ]}' > "$DATA_DIR/products.json"
}

create_products() {
    run "$REPO_ROOT/tools/shopware/create-products.sh" "$@"
}

# The body of the n-th product create, counted from 1.
product_body() {
    grep '^POST /api/product ' "$STUB_SW_LOG" | sed -n "${1}p" | sed 's|^POST /api/product ||'
}

count() {
    grep -c "$1" "$STUB_SW_LOG" || true
}

@test "help needs no credentials and names the switch" {
    unset SW_API_URL
    export SHOPWARE_MCP_CONFIG=/nonexistent
    create_products --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"print-models.json"* ]]
}

@test "an unknown option is rejected" {
    create_products "$DATA_DIR/products.json" --frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a missing data file explains itself" {
    create_products
    [ "$status" -ne 0 ]
    [[ "$output" == *"no data file"* ]]
}

@test "a missing image stops the run before any request" {
    rm "$DATA_DIR/media/ex-c.png"
    create_products "$DATA_DIR/products.json" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing image"* ]]
    [ ! -s "$STUB_SW_LOG" ]
}

@test "a dry run writes nothing and names both products" {
    create_products "$DATA_DIR/products.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"EX-1 \"Example One\""* ]]
    [[ "$output" == *"EX-2 \"Example Two\""* ]]
    [[ "$output" == *"would create 2, skipped 0"* ]]
    [ "$(count '^POST /api/product ')" -eq 0 ]
    [ "$(count '^POST /api/media ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

@test "apply uploads every image, creates both products and clears the cache" {
    create_products "$DATA_DIR/products.json" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"created 2, skipped 0"* ]]
    [ "$(count '^POST /api/media ')" -eq 3 ]
    [ "$(count '^POST /api/_action/media/.*/upload?extension=png&fileName=ex-c')" -eq 1 ]
    [ "$(count '^POST /api/product ')" -eq 2 ]
    [ "$(count '^DELETE /api/_action/cache')" -eq 1 ]
}

@test "a new product is visible but not orderable, at price 0 with its purchase price" {
    create_products "$DATA_DIR/products.json" --apply
    body="$(product_body 1)"
    [ "$(jq -c '[.active, .stock, .isCloseout, .price[0].gross, .purchasePrices[0].gross]' <<<"$body")" = '[true,0,true,0,1.75]' ]
    [ "$(jq -c '[.categories[].id]' <<<"$body")" = '["cat1","cat2"]' ]
    [ "$(jq -r '.visibilities[0].salesChannelId' <<<"$body")" = "sc1" ]
    [ "$(jq -r '.translations["lang-de"].name' <<<"$body")" = "Beispiel Eins" ]
    [ "$(jq -c '[.weight, .width, .height, .length]' <<<"$body")" = '[0.033,41,80,43]' ]
    [ "$(jq -c '.price[0].listPrice' <<<"$body")" = 'null' ]
}

@test "a list price is sent crossed out next to the price of 0" {
    jq '.products[0].listPrice = 5' "$DATA_DIR/products.json" > "$DATA_DIR/p.json" && mv "$DATA_DIR/p.json" "$DATA_DIR/products.json"
    create_products "$DATA_DIR/products.json" --apply
    [ "$(jq -c '.price[0] | [.gross, .listPrice.gross, .listPrice.net, .listPrice.currencyId]' <<<"$(product_body 1)")" = '[0,5,5,"eur1"]' ]
}

@test "the first image becomes the cover, in the order of the data file" {
    create_products "$DATA_DIR/products.json" --apply
    body="$(product_body 1)"
    [ "$(jq '.media | length' <<<"$body")" -eq 2 ]
    [ "$(jq -r '.coverId == .media[0].id' <<<"$body")" = "true" ]
    [ "$(jq -c '[.media[].position]' <<<"$body")" = '[0,1]' ]
}

@test "an existing product number is skipped as a whole" {
    printf '{"data":[{"id":"p-existing"}],"total":1}' > "$STUB_SW_DIR/_api_search_product"
    create_products "$DATA_DIR/products.json" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip"*"EX-1 exists (p-existing)"* ]]
    [[ "$output" == *"created 0, skipped 2"* ]]
    [ "$(count '^POST /api/product ')" -eq 0 ]
    [ "$(count '^POST /api/media ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

# EX-1 exists with ex-b only, at position 0 and as the cover; ex-a is in the library.
existing_with_one_image() {
    printf '{"data":[{"id":"p-existing","coverId":"row-b","media":[{"id":"row-b","mediaId":"m-b","position":0}]}],"total":1}' \
        > "$STUB_SW_DIR/_api_search_product"
    printf '{"data":[{"id":"m-b"}],"total":1}' > "$STUB_SW_DIR/_api_search_media"
}

@test "sync-media in a dry run names the change and writes nothing" {
    existing_with_one_image
    create_products "$DATA_DIR/products.json" --sync-media
    [ "$status" -eq 0 ]
    [[ "$output" == *"EX-1 images set to the 2 listed, the first as cover"* ]]
    [[ "$output" == *"EX-2 images already current"* ]]
    [[ "$output" == *"would sync images of 1"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
}

@test "sync-media keeps an existing row and moves it to the front as the cover" {
    printf '{"data":[{"id":"p-existing","coverId":"row-z","media":[{"id":"row-z","mediaId":"m-z","position":0},{"id":"row-b","mediaId":"m-b","position":1}]}],"total":1}' \
        > "$STUB_SW_DIR/_api_search_product"
    printf '{"data":[{"id":"m-b"}],"total":1}' > "$STUB_SW_DIR/_api_search_media"
    jq '.products[0].media = ["media/ex-b.jpg"] | .products |= .[0:1]' "$DATA_DIR/products.json" > "$DATA_DIR/p.json"
    create_products "$DATA_DIR/p.json" --sync-media --apply
    [ "$status" -eq 0 ]
    body="$(grep '^PATCH /api/product/p-existing ' "$STUB_SW_LOG" | sed 's|^PATCH /api/product/p-existing ||')"
    [ "$body" = '{"media":[{"id":"row-b","mediaId":"m-b","position":0}],"coverId":"row-b"}' ]
    [ "$(count '^POST /api/media ')" -eq 0 ]
    [ "$(count '^DELETE /api/_action/cache')" -eq 1 ]
}

@test "sync-media uploads a missing image and adds it as a new row" {
    printf '{"data":[{"id":"p-existing","coverId":null,"media":[]}],"total":1}' > "$STUB_SW_DIR/_api_search_product"
    jq '.products |= .[1:2]' "$DATA_DIR/products.json" > "$DATA_DIR/p.json"
    create_products "$DATA_DIR/p.json" --sync-media --apply
    [ "$status" -eq 0 ]
    [ "$(count '^POST /api/media ')" -eq 1 ]
    body="$(grep '^PATCH /api/product/p-existing ' "$STUB_SW_LOG" | sed 's|^PATCH /api/product/p-existing ||')"
    [ "$(jq -r '[(.media | length), (.media[0].id | length), (.coverId == .media[0].id)] | map(tostring) | join(" ")' <<<"$body")" = "1 32 true" ]
    [ "$(count '^POST /api/product ')" -eq 0 ]
}

@test "sync-media leaves a product alone whose images already match" {
    printf '{"data":[{"id":"p-existing","coverId":"row-x","media":[{"id":"row-x","mediaId":"m-x","position":0}]}],"total":1}' \
        > "$STUB_SW_DIR/_api_search_product"
    printf '{"data":[{"id":"m-x"}],"total":1}' > "$STUB_SW_DIR/_api_search_media"
    jq '.products[1].media = ["media/ex-c.png"] | .products |= .[1:2]' "$DATA_DIR/products.json" > "$DATA_DIR/p.json"
    create_products "$DATA_DIR/p.json" --sync-media --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"EX-2 images already current"* ]]
    [[ "$output" == *"synced images of 0"* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

@test "an image already in the media library is reused, not uploaded again" {
    printf '{"data":[{"id":"m-existing"}],"total":1}' > "$STUB_SW_DIR/_api_search_media"
    create_products "$DATA_DIR/products.json" --apply
    [ "$status" -eq 0 ]
    [ "$(count '^POST /api/media ')" -eq 0 ]
    [ "$(jq -r '.media[0].mediaId' <<<"$(product_body 1)")" = "m-existing" ]
}

@test "a refused token stops the run before it writes" {
    export STUB_SW_NO_TOKEN=1
    create_products "$DATA_DIR/products.json" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"access token"* ]]
    [ "$(count '^POST /api/product ')" -eq 0 ]
}

@test "the shipped print-model data names existing images and no trademark" {
    create_products "$REPO_ROOT/tools/shopware/products/print-models.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create 3, skipped 0"* ]]
    run grep -ci tecnare "$REPO_ROOT/tools/shopware/products/print-models.json"
    [ "$output" = "0" ]
}
