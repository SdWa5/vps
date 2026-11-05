#!/usr/bin/env bats
#
# The effective sshd settings of hardening/sshd_config.d/10-hardening.conf, read through a main
# config shaped like Debian's: the drop-in Include first, then settings for everyone. The relay
# Match block must cap the relay account and must not leak into those later lines.

load test_helper

setup() {
    common_setup
    CONF_DIR="$BATS_TEST_TMPDIR/sshd_config.d"
    MAIN="$BATS_TEST_TMPDIR/sshd_config"
    HOSTKEY="$BATS_TEST_TMPDIR/host_ed25519"
    mkdir -p "$CONF_DIR"
    cp "$REPO_ROOT/hardening/sshd_config.d/10-hardening.conf" "$CONF_DIR/"
    printf 'Include %s/*.conf\nX11Forwarding yes\nSubsystem sftp internal-sftp\n' "$CONF_DIR" > "$MAIN"
    ssh-keygen -q -t ed25519 -N '' -f "$HOSTKEY"
}

effective() {
    run sshd -T -f "$MAIN" -h "$HOSTKEY" -C "user=$1,host=h,addr=203.0.113.9"
    [ "$status" -eq 0 ]
}

@test "the drop-in passes sshd's own check" {
    run sshd -t -f "$MAIN" -h "$HOSTKEY"
    [ "$status" -eq 0 ]
}

@test "relay gets the ceiling: two listen ports, two open ports, no agent, tty or X11" {
    effective relay
    [[ "$output" == *$'\npermitlisten localhost:2201 localhost:2202\n'* ]]
    [[ "$output" == *$'\npermitopen 127.0.0.1:2201 127.0.0.1:2202\n'* ]]
    [[ "$output" == *$'\nauthorizedkeysfile /etc/ssh/relay_authorized_keys\n'* ]]
    [[ "$output" == *$'\nallowagentforwarding no\n'* ]]
    [[ "$output" == *$'\nallowstreamlocalforwarding no\n'* ]]
    [[ "$output" == *$'\nx11forwarding no\n'* ]]
    [[ "$output" == *$'\npermittty no\n'* ]]
    [[ "$output" == *$'\nforcecommand /usr/sbin/nologin\n'* ]]
    [[ "$output" == *$'\nclientaliveinterval 15\n'* ]]
    [[ "$output" == *$'\nclientalivecountmax 3\n'* ]]
}

@test "root keeps the main config's settings, so the Match block ends with its file" {
    effective root
    [[ "$output" == *$'\npermitlisten any\n'* ]]
    [[ "$output" == *$'\npermitopen any\n'* ]]
    [[ "$output" == *$'\nx11forwarding yes\n'* ]]
    [[ "$output" == *$'\nauthorizedkeysfile .ssh/authorized_keys\n'* ]]
    [[ "$output" == *$'\npermittty yes\n'* ]]
}

@test "only root and relay may log in" {
    effective root
    [[ "$output" == *$'\nallowusers root\n'* ]]
    [[ "$output" == *$'\nallowusers relay\n'* ]]
    [ "$(printf '%s\n' "$output" | grep -c '^allowusers ')" -eq 2 ]
}
