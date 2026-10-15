#!/usr/bin/env bats
# Tests for the Docker wrappers under tools/shopware/images/ and
# tools/shopware/print-cost/. What runs inside the images is covered by
# tests/shopware-merch-tools.py; this suite checks the wrappers' own logic.

load test_helper

setup() {
    common_setup
}

print_cost() {
    run "$REPO_ROOT/tools/shopware/print-cost/print-cost.sh" "$@"
}

shop_images() {
    run "$REPO_ROOT/tools/shopware/images/shop-images.sh" "$@"
}

@test "print-cost: help names the inputs" {
    print_cost --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"FILAMENT_EUR_KG"* ]]
    [[ "$output" == *"Labour is not included"* ]]
}

@test "print-cost: an unknown option is rejected" {
    print_cost --frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "print-cost: a missing STL stops before docker" {
    print_cost "$BATS_TEST_TMPDIR/nope.stl"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read"* ]]
}

# The slicer measured 33.14 g in 1 h 36 m 12 s and 56.37 g in 2 h 18 m for the
# two print models; merch.md carries 1.75 and 2.77 as their purchase prices.
@test "print-cost: the default inputs give the purchase prices in merch.md" {
    PRINT_COST_ONLY=1 print_cost 33.14 5772
    [ "$output" = "1.75" ]
    PRINT_COST_ONLY=1 print_cost 56.37 8280
    [ "$output" = "2.77" ]
}

@test "print-cost: every input can be overridden" {
    FILAMENT_EUR_KG=20 POWER_W=0 PRINTER_EUR=0 FAILURE=0 PRINT_COST_ONLY=1 print_cost 100 3600
    [ "$output" = "2.00" ]
}

@test "shop-images: help names both commands" {
    shop_images --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"run JOBS IN_DIR OUT_DIR"* ]]
    [[ "$output" == *"corners PHOTO"* ]]
}

@test "shop-images: an unknown command is rejected" {
    shop_images frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "shop-images: run checks its arguments before docker" {
    shop_images run "$BATS_TEST_TMPDIR/none.jobs" "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read"* ]]
    shop_images run "$REPO_ROOT/tools/shopware/images/print-models.jobs" "$BATS_TEST_TMPDIR/missing" "$BATS_TEST_TMPDIR/out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no directory"* ]]
}
