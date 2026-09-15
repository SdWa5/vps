#!/usr/bin/env bats
# Tests for monitoring/chimodiazz-deploy.sh

load test_helper

setup() {
    common_setup
    chimo_deploy_setup
}

# --- the ordinary run ------------------------------------------------------

@test "an unchanged commit deploys nothing and sends nothing" {
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    # A reset is what a deployment looks like. Its absence is the assertion.
    [[ "$(chimo_git_calls)" != *"reset"* ]]
}

@test "an unchanged commit still asks the remote" {
    chimo_deploy
    [[ "$(chimo_git_calls)" == *"fetch"* ]]
}

@test "--force deploys an unchanged commit" {
    chimo_deploy --force
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$(chimo_git_calls)" == *"reset"* ]]
}

# --- a real deployment -----------------------------------------------------

@test "a new commit is deployed and stays silent when it works" {
    chimo_new_commit
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$(chimo_git_calls)" == *"reset --hard 2222222222222222222222222222222222222222"* ]]
}

# --- failures --------------------------------------------------------------

@test "a failed fetch alerts and names the deploy key, without touching the site" {
    STUB_GIT_FETCH_RC=1 chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"github-chimodiazz"* ]]
    [[ "$(chimo_git_calls)" != *"reset"* ]]
}

@test "a branch that no longer exists alerts rather than deploying nothing quietly" {
    unset STUB_GIT_REMOTE
    chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"branch gone"* ]]
}

@test "a detached checkout alerts instead of guessing a branch" {
    STUB_GIT_BRANCH=HEAD chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"not on a branch"* ]]
}

@test "a missing checkout alerts" {
    SRC_DIR="$BATS_TEST_TMPDIR/nowhere" chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"no checkout"* ]]
}

@test "a failed theme compile rolls back to the previous commit" {
    chimo_new_commit
    STUB_THEME_COMPILE_FAILS=1 chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"rolled back"* ]]
    # Forward to the new commit, then back to the old one.
    [[ "$(chimo_git_calls)" == *"reset --hard 2222222222222222222222222222222222222222"* ]]
    [[ "$(chimo_git_calls)" == *"reset --hard 1111111111111111111111111111111111111111"* ]]
}

@test "a failed compile carries the command output into the mail" {
    chimo_new_commit
    STUB_THEME_COMPILE_FAILS=1 chimo_deploy
    [[ "$(mail_body)" == *"sass exploded"* ]]
}

@test "a site that does not come back rolls back too" {
    chimo_new_commit
    STUB_HTTP_CODE=500 HEALTH_TIMEOUT=0 chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"did not answer 200"* ]]
    [[ "$(chimo_git_calls)" == *"reset --hard 1111111111111111111111111111111111111111"* ]]
}

@test "plugin:update failing is not a deployment failure" {
    # It exits non-zero when there is nothing to update, which is the ordinary
    # case for a content change that left the plugin version alone.
    chimo_new_commit
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
}

# --- interface -------------------------------------------------------------

@test "the dry run reports the branch and changes nothing" {
    chimo_deploy --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"main"* ]]
    [[ "$(chimo_git_calls)" != *"fetch"* ]]
    [ "$(mail_count)" -eq 0 ]
}

@test "help explains which branch is deployed" {
    chimo_deploy --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"checked out on"* ]]
}

@test "an unknown option is rejected" {
    chimo_deploy --wat
    [ "$status" -eq 2 ]
}
