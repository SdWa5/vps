#!/usr/bin/env bats
# Tests for send_mail in monitoring/lib.sh: relay by default, login only with a password.

load test_helper

setup() {
    common_setup
    unset MONITOR_SMTP_PASSWORD MONITOR_SMTP_HOST MONITOR_SMTP_PORT MONITOR_SMTP_USER MONITOR_SMTP_FROM
    export STUB_MAIL_CONFIG="$BATS_TEST_TMPDIR/mail.config"
    export STUB_MAIL_ARGS="$BATS_TEST_TMPDIR/mail.args"
    # shellcheck source=../monitoring/lib.sh
    source "$REPO_ROOT/monitoring/lib.sh"
}

@test "without a password the mail goes to the relay with STARTTLS and no login" {
    run send_mail "subject" "body"
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--url smtp://smtp-relay.gmail.com:587"* ]]
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--ssl-reqd"* ]]
    [ ! -s "$STUB_MAIL_CONFIG" ]
}

@test "the envelope sender defaults to the domain mailbox" {
    run send_mail "subject" "body"
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--mail-from ripper@sdwa5.org"* ]]
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--mail-rcpt alerts@example.com"* ]]
}

@test "a password adds a login through stdin and never through the arguments" {
    MONITOR_SMTP_PASSWORD=secret-value run send_mail "subject" "body"
    [ "$status" -eq 0 ]
    [[ "$(cat "$STUB_MAIL_CONFIG")" == 'user = "ripper@sdwa5.org:secret-value"' ]]
    [[ "$(cat "$STUB_MAIL_ARGS")" != *"secret-value"* ]]
}

@test "port 465 switches to implicit TLS" {
    MONITOR_SMTP_HOST=smtp.example.com MONITOR_SMTP_PORT=465 run send_mail "subject" "body"
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--url smtps://smtp.example.com:465"* ]]
    [[ "$(cat "$STUB_MAIL_ARGS")" == *"--ssl-reqd"* ]]
}

@test "a failed delivery is reported to the caller" {
    STUB_MAIL_RC=55 run send_mail "subject" "body"
    [ "$status" -eq 55 ]
}
