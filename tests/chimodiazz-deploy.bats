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

@test "a fetch that fails once is logged and mails nothing" {
    STUB_GIT_FETCH_RC=1 STUB_GIT_FETCH_ERR="ssh: connect to host github.com port 22: Connection timed out" chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$output" == *"Connection timed out"* ]]
    [[ "$(chimo_git_calls)" != *"reset"* ]]
}

@test "a fetch that keeps failing past the grace alerts with git's words and names the deploy key" {
    export STUB_GIT_FETCH_RC=1 STUB_GIT_FETCH_ERR="ERROR: Repository not found."
    FAKE_NOW=1000000 chimo_deploy
    FAKE_NOW=1000600 chimo_deploy
    [ "$(mail_count)" -eq 0 ]
    FAKE_NOW=1000900 chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"github-chimodiazz"* ]]
    [[ "$(mail_body)" == *"Repository not found."* ]]
    [[ "$(chimo_git_calls)" != *"reset"* ]]
}

@test "a lasting fetch failure reminds after a day rather than every run" {
    export STUB_GIT_FETCH_RC=1 FETCH_GRACE=0
    FAKE_NOW=1000000 chimo_deploy
    FAKE_NOW=1000300 chimo_deploy
    FAKE_NOW=1086300 chimo_deploy
    [ "$(mail_count)" -eq 1 ]
    FAKE_NOW=1086400 chimo_deploy
    [ "$(mail_count)" -eq 2 ]
    [[ "$(mail_body)" == *"reminder 2"* ]]
}

@test "a remote that is reachable again after an alert says so once" {
    STUB_GIT_FETCH_RC=1 FETCH_GRACE=0 chimo_deploy
    [ "$(mail_count)" -eq 1 ]
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 2 ]
    [[ "$(mail_body)" == *"reachable again"* ]]
    chimo_deploy
    [ "$(mail_count)" -eq 2 ]
}

@test "a remote that recovers within the grace stays silent" {
    STUB_GIT_FETCH_RC=1 chimo_deploy
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ ! -e "$STATE_DIR/chimodiazz-deploy-remote" ]]
}

@test "a branch deleted upstream alerts as gone without waiting out the grace" {
    STUB_GIT_FETCH_RC=128 STUB_GIT_FETCH_ERR="fatal: couldn't find remote ref main" chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"branch gone"* ]]
    [[ "$(mail_body)" == *"couldn't find remote ref main"* ]]
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

# --- the path filter -------------------------------------------------------

@test "a documentation-only commit moves the checkout without rebuilding" {
    chimo_docs_only_commit
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$(chimo_git_calls)" == *"reset --hard 2222222222222222222222222222222222222222"* ]]
    [[ "$(chimo_docker_calls)" != *"theme:compile"* ]]
}

@test "a commit that touches the theme is rebuilt" {
    chimo_new_commit
    chimo_deploy
    [ "$status" -eq 0 ]
    [[ "$(chimo_docker_calls)" == *"theme:compile"* ]]
}

@test "--force rebuilds a documentation-only commit anyway" {
    chimo_docs_only_commit
    chimo_deploy --force
    [ "$status" -eq 0 ]
    [[ "$(chimo_docker_calls)" == *"theme:compile"* ]]
}

@test "a diff that cannot be computed rebuilds rather than skipping" {
    # Skipping a real theme change leaves the site stale with nothing saying so,
    # which is worse than compiling for nothing.
    chimo_docs_only_commit
    STUB_GIT_DIFF_RC=1 chimo_deploy
    [ "$status" -eq 0 ]
    [[ "$(chimo_docker_calls)" == *"theme:compile"* ]]
}

@test "an empty REBUILD_PATHS turns the filter off" {
    chimo_docs_only_commit
    REBUILD_PATHS= chimo_deploy
    [ "$status" -eq 0 ]
    [[ "$(chimo_docker_calls)" == *"theme:compile"* ]]
}

# --- the cache race --------------------------------------------------------

@test "a cache:clear that fails once is retried instead of rolling back" {
    chimo_new_commit
    STUB_CACHE_CLEAR_FAIL_ONCE="$BATS_TEST_TMPDIR/cache-failed-once" chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$(chimo_docker_calls)" == *"rm -rf var/cache/prod_*"* ]]
    [[ "$(chimo_git_calls)" != *"reset --hard 1111111111111111111111111111111111111111"* ]]
}

@test "a cache:clear that keeps failing still rolls back" {
    chimo_new_commit
    STUB_CACHE_CLEAR_FAILS=1 chimo_deploy
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"rolled back"* ]]
    [[ "$(chimo_git_calls)" == *"reset --hard 1111111111111111111111111111111111111111"* ]]
}

# --- the lock --------------------------------------------------------------

@test "a run whose lock is already held exits silently" {
    chimo_new_commit
    exec 200>"$LOCK_FILE"
    flock -n 200
    chimo_deploy
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    [[ "$(chimo_git_calls)" != *"reset"* ]]
    flock -u 200
}

# --- interface -------------------------------------------------------------

@test "the dry run reports the branch and changes nothing" {
    chimo_deploy --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"main"* ]]
    [[ "$output" == *"shopware/"* ]]
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
