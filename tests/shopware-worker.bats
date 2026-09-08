#!/usr/bin/env bats
# Tests for monitoring/shopware-worker.sh

load test_helper

setup() {
    common_setup
}

worker() {
    run "$REPO_ROOT/monitoring/shopware-worker.sh" "$@"
}

@test "a healthy run sends no mail" {
    worker
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
}

@test "the dry run reports both commands and changes nothing" {
    worker --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"scheduled-task:run"* ]]
    [[ "$output" == *"messenger:consume"* ]]
    [ "$(mail_count)" -eq 0 ]
}

@test "the dry run names the transports, including failed" {
    worker --dry-run
    # Shopware's documentation warns that without the failed transport a failed
    # message is never retried and sits there forever.
    [[ "$output" == *"async low_priority failed"* ]]
}

@test "a failing scheduled-task run mails and exits non-zero" {
    STUB_TASK_RUN_FAILS=1 worker
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"scheduled tasks failed"* ]]
    [[ "$(mail_body)" == *"task run blew up"* ]]
}

@test "a failing consumer mails and exits non-zero" {
    STUB_CONSUME_FAILS=1 worker
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"queue consumer failed"* ]]
}

@test "the scheduled tasks run before the consumer" {
    # If the consumer ran first it would process messages the tasks are about to
    # enqueue only on the next minute, so the order is deliberate.
    STUB_TASK_RUN_FAILS=1 worker
    [[ "$(mail_body)" != *"queue consumer"* ]]
}

@test "a container that is not running mails rather than failing silently" {
    STUB_CONTAINER_shopware="" worker
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"is not running"* ]]
}

@test "an unknown option is rejected" {
    worker --nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "help exits zero and needs no container" {
    STUB_CONTAINER_shopware="" worker --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"shopware-worker.sh"* ]]
}
