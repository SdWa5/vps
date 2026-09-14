#!/usr/bin/env bats
# Tests for tools/dolibarr/sync-pm.sh

load test_helper

setup() {
    common_setup
    doli_pm_setup
}

@test "help works without a key file or a spec" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    export DOLIBARR_PM_SPEC="$BATS_TEST_TMPDIR/also-not-there"
    doli_sync_pm --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
}

@test "an unknown option is rejected" {
    doli_sync_pm --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a missing key file explains itself" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"no API key at"* ]]
}

@test "a missing spec explains itself" {
    export DOLIBARR_PM_SPEC="$BATS_TEST_TMPDIR/does-not-exist"
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"no spec at"* ]]
}

@test "a spec that does not parse is refused" {
    doli_pm_spec 'this is not json'
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not parse"* ]]
}

@test "a project without a title is refused" {
    doli_pm_spec '{"projects":[{"tasks":[]}]}'
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-empty title"* ]]
}

@test "a task without a label is refused" {
    doli_pm_spec '{"projects":[{"title":"Inventur","tasks":[{"description":"x"}]}]}'
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"without a label"* ]]
}

@test "a dry run writes nothing" {
    doli_sync_pm
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [ "$(doli_post_count)" -eq 0 ]
    [ "$(doli_put_count)" -eq 0 ]
}

@test "a dry run names the new project and every task" {
    doli_sync_pm
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip     project Inventur"* ]]
    [[ "$output" == *"would    project Krampustek"* ]]
    [[ "$output" == *"task Eurokisten kaufen"* ]]
    [[ "$output" == *"task Rendering"* ]]
    [[ "$output" == *"3 to create, 0 to update, 1 already current"* ]]
}

@test "apply creates only the project the ERP lacks" {
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$(printf '%s\n' "$output" | grep -c '^POST projects ')" -eq 1 ]]
    line="$(printf '%s\n' "$output" | grep '^POST projects ')"
    [[ "$line" == *"Krampustek"* ]]
    [[ "$line" != *"Inventur"* ]]
}

@test "a created project carries its own fields and an auto ref" {
    doli_sync_pm --apply
    run doli_requests
    line="$(printf '%s\n' "$output" | grep '^POST projects')"
    [[ "$line" == *'"ref":"auto"'* ]]
    [[ "$line" == *'"title":"Krampustek"'* ]]
    [[ "$line" == *'"description":"Next event"'* ]]
    [[ "$line" == *'"usage_task":1'* ]]
}

# A project created over the API is a draft and holds no tasks in the UI's eyes,
# where every project made by hand is open.
@test "a created project is validated straight away" {
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$output" == *"POST projects/100/validate"* ]]
    [[ "$output" == *'"notrigger":0'* ]]
}

@test "a project that is already open is not validated again" {
    doli_pm_spec '{"projects":[{"title":"Inventur","tasks":[]}]}'
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$output" != *"validate"* ]]
}

# A draft left behind by an earlier run, before the script learned to validate.
@test "an existing project still in draft is validated" {
    doli_pm_projects "$(jq -n '[{id:"3",title:"Inventur",statut:"0",usage_task:1}]')"
    doli_pm_spec '{"projects":[{"title":"Inventur","tasks":[]}]}'
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$output" == *"POST projects/3/validate"* ]]
}

@test "every task is created with an auto ref and a project id" {
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$(printf '%s\n' "$output" | grep -c '^POST tasks')" -eq 2 ]]
    [[ "$output" == *'"label":"Eurokisten kaufen"'* ]]
    [[ "$output" == *'"ref":"auto"'* ]]
}

# The task pass of a freshly created project has to use the id the create
# answered with, not the id of some project that already existed.
@test "a task of a new project lands under the id the create returned" {
    doli_sync_pm --apply
    run doli_requests
    existing="$(printf '%s\n' "$output" | grep '"label":"Eurokisten kaufen"')"
    [[ "$existing" == *'"fk_project":3'* ]]
    created="$(printf '%s\n' "$output" | grep '"label":"Rendering"')"
    [[ "$created" == *'"fk_project":100'* ]]
}

@test "a date goes out as epoch seconds" {
    doli_sync_pm --apply
    run doli_requests
    line="$(printf '%s\n' "$output" | grep '"label":"Rendering"')"
    [[ "$line" == *'"date_end":1789776000'* ]]
}

# The idempotency claim. An ERP that already matches the spec is left alone.
@test "a second run over a matching ERP writes nothing" {
    doli_pm_projects "$(jq -n '[
        {id:"3",title:"Inventur",description:"Inventur",date_start:1759104000,date_end:"",
         public:"0",statut:"1",usage_task:1},
        {id:"9",title:"Krampustek",description:"Next event",date_start:1789776000,
         date_end:1789776000,public:"0",statut:"1",usage_task:1}
    ]')"
    doli_pm_tasks "$(jq -n '[
        {id:"11",fk_project:"3",label:"Eurokisten kaufen"},
        {id:"12",fk_project:"9",label:"Rendering",date_end:1789776000}
    ]')"

    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to create, 0 to update, 4 already current"* ]]
    [ "$(doli_post_count)" -eq 0 ]
    [ "$(doli_put_count)" -eq 0 ]
}

# An unset number on the server and a zero in the spec are the same thing. If
# they were not, every run would rewrite progress and nothing would be idempotent.
@test "a progress of zero against a null on the server is not a change" {
    doli_pm_spec "$(jq -n '{projects:[{title:"Inventur",
        tasks:[{label:"Eurokisten kaufen", progress:0}]}]}')"
    doli_pm_tasks "$(jq -n '[{id:"11",fk_project:"3",label:"Eurokisten kaufen",progress:null}]')"
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to create, 0 to update"* ]]
    [ "$(doli_put_count)" -eq 0 ]
}

@test "a changed field produces one PUT carrying only that field" {
    doli_pm_spec "$(jq -n '{projects:[{title:"Inventur",
        tasks:[{label:"Eurokisten kaufen", description:"neu", date_end:"2026-09-19"}]}]}')"
    doli_pm_tasks "$(jq -n '[{id:"11",fk_project:"3",label:"Eurokisten kaufen",
        description:"neu",date_end:1700000000}]')"
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    [ "$(doli_put_count)" -eq 1 ]
    run doli_requests
    line="$(printf '%s\n' "$output" | grep '^PUT tasks/11')"
    [[ "$line" == *'"date_end":1789776000'* ]]
    [[ "$line" != *"description"* ]]
}

# A title that differs only in case is the same project typed twice, and the
# API offers no way to undo the duplicate it would otherwise create.
@test "a project whose title differs only in case aborts before any write" {
    doli_pm_spec '{"projects":[{"title":"BUERO","tasks":[]}]}'
    doli_sync_pm --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to create a second one"* ]]
    [ "$(doli_post_count)" -eq 0 ]
}

@test "a project the spec does not name is never touched" {
    doli_sync_pm --apply
    run doli_requests
    [[ "$output" != *"projects/4"* ]]
}

@test "nothing is ever deleted" {
    doli_sync_pm --apply
    run doli_requests
    [[ "$output" != *"DELETE"* ]]
}

@test "an empty task collection arrives as a 404 and is not an error" {
    doli_pm_tasks '{"error":{"code":404,"message":"Not Found"}}'
    doli_sync_pm
    [ "$status" -eq 0 ]
    [[ "$output" == *"task Eurokisten kaufen"* ]]
}

@test "a project list that is neither a list nor a 404 fails loudly" {
    doli_pm_projects '{"error":{"code":401,"message":"Unauthorized"}}'
    doli_sync_pm
    [ "$status" -eq 1 ]
    [[ "$output" == *"did not return a list"* ]]
}

@test "the key travels in a header and never in the argument list" {
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    grep -q 'DOLAPIKEY' "$STUB_DOLI_CONFIG"
    ! grep -q 'fake-api-key' "$STUB_DOLI_ARGS"
}

# Dolibarr HTML-escapes what it stores, so "Allen & Heath" comes back as
# "Allen &amp; Heath". Measured on the live instance on 2026-09-15, where this
# rewrote the same task on every run.
@test "an ampersand in a description is not a change" {
    doli_pm_spec "$(jq -n '{projects:[{title:"Inventur",
        tasks:[{label:"Eurokisten kaufen", description:"Allen & Heath Xone:92."}]}]}')"
    doli_pm_tasks "$(jq -n '[{id:"11",fk_project:"3",label:"Eurokisten kaufen",
        description:"Allen &amp; Heath Xone:92."}]')"
    doli_sync_pm --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to create, 0 to update"* ]]
    [ "$(doli_put_count)" -eq 0 ]
}

# The per-project endpoint hides the tasks of a project the API user is not a
# contact on, and a contact cannot be added over this API.
@test "tasks are read from the global list, not per project" {
    doli_sync_pm
    [ "$status" -eq 0 ]
    run doli_requests
    [[ "$output" == *"GET tasks?limit="* ]]
    [[ "$output" != *"/tasks "* ]]
}
