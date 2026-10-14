#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    export STUB_FK_APPLIED="$BATS_TEST_TMPDIR/applied.sql"
    export STUB_DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    export STUB_FK_SNAPSHOT=$'llx_a\tfk_a_b\tllx_b\t`fk_b`\t`rowid`\tRESTRICT\tRESTRICT\t1\t1\nllx_c\tfk_c_d\tllx_d\t`x`, `y`\t`x`, `y`\tCASCADE\tSET NULL\t1\t2'
}

recreate() {
    run bash "$REPO_ROOT/tools/mariadb/recreate-foreign-keys.sh" "$@"
}

@test "the dry run prints a drop and an add per key and changes nothing" {
    recreate fkdb
    [ "$status" -eq 0 ]
    [[ "$output" == *'ALTER TABLE `llx_a` DROP FOREIGN KEY `fk_a_b`, ALGORITHM=INPLACE, LOCK=NONE;'* ]]
    [[ "$output" == *'ALTER TABLE `llx_a` ADD CONSTRAINT `fk_a_b` FOREIGN KEY (`fk_b`) REFERENCES `llx_b` (`rowid`), ALGORITHM=INPLACE, LOCK=NONE;'* ]]
    [[ "$output" == *'Nothing was changed'* ]]
    [ ! -f "$STUB_FK_APPLIED" ]
}

@test "non-default rules and multi-column keys are carried over, RESTRICT is left implicit" {
    recreate fkdb
    [[ "$output" == *'FOREIGN KEY (`x`, `y`) REFERENCES `llx_d` (`x`, `y`) ON DELETE CASCADE ON UPDATE SET NULL, ALGORITHM'* ]]
    [[ "$output" != *'ON DELETE RESTRICT'* ]]
}

@test "apply runs with foreign key checks off and verifies the definitions" {
    recreate fkdb --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *'2 foreign keys recreated; definitions unchanged.'* ]]
    [ "$(head -1 "$STUB_FK_APPLIED")" = 'SET SESSION foreign_key_checks = 0;' ]
    [ "$(tail -1 "$STUB_FK_APPLIED")" = 'SET SESSION foreign_key_checks = 1;' ]
    [ "$(grep -c '^ALTER TABLE' "$STUB_FK_APPLIED")" -eq 4 ]
}

@test "existing duplicates are refused, because they would be recreated as pairs" {
    STUB_FK_DUPLICATES=3 recreate fkdb --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *'3 duplicate foreign key name(s) exist'* ]]
    [ ! -f "$STUB_FK_APPLIED" ]
}

@test "a definition that differs afterwards fails and prints the snapshot" {
    export STUB_FK_SNAPSHOT_AFTER=$'llx_a\tfk_a_b\tllx_b\t`fk_b`\t`rowid`\tRESTRICT\tRESTRICT\t1\t1'
    recreate fkdb --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *'differ from the snapshot'* ]]
    [[ "$output" == *'fk_c_d'* ]]
}

@test "an error during apply fails and prints the snapshot" {
    STUB_FK_APPLY_FAIL=1 recreate fkdb --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *'Recreating stopped at an error'* ]]
    [[ "$output" == *'fk_c_d'* ]]
}

@test "a cross-schema key is refused before anything is sent" {
    export STUB_FK_SNAPSHOT=$'llx_a\tfk_a_b\tllx_b\t`fk_b`\t`rowid`\tRESTRICT\tRESTRICT\t0\t1'
    recreate fkdb --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *'cross-schema'* ]]
    [ ! -f "$STUB_FK_APPLIED" ]
}

@test "missing, invalid and unknown arguments fail without a query" {
    : > "$STUB_DOCKER_LOG"
    recreate
    [ "$status" -eq 2 ]
    recreate '../x'
    [ "$status" -eq 2 ]
    recreate fkdb --force
    [ "$status" -eq 2 ]
    [ ! -s "$STUB_DOCKER_LOG" ]
    recreate --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'--apply'* ]]
}
