#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    ETC_DIR="$ACCOUNT_CHECK_ETC"
}

account_check() {
    run bash "$REPO_ROOT/monitoring/account-check.sh" "$@"
}

@test "the healthy host is OK and names root and its one allowed key" {
    account_check
    [ "$status" -eq 0 ]
    [[ "$output" == OK$'\t'* ]]
    [[ "$output" == *"login accounts: root;"* ]]
    [[ "$output" == *"1 root key(s), all allowed"* ]]
}

@test "the cloud-init account of 2026-10-24 is CRIT without printing its sudoers rules" {
    printf 'debian:x:1001:1001:Debian:/home/debian:/bin/bash\n' >> "$ETC_DIR/passwd"
    sed -i 's/^sudo:x:27:$/sudo:x:27:debian/' "$ETC_DIR/group"
    cat > "$ETC_DIR/sudoers.d/90-cloud-init-users" <<'EOF'
# Created by cloud-init v. 25.1.4 on Wed, 15 Oct 2026 17:16:02 +0000

# User rules for root
root ALL=(ALL) NOPASSWD:ALL

# User rules for debian
debian ALL=(ALL) NOPASSWD:ALL
EOF
    account_check
    [ "$status" -eq 0 ]
    [[ "$output" == CRIT$'\t'* ]]
    [[ "$output" == *"unexpected login account(s): debian"* ]]
    [[ "$output" == *"sudo=debian"* ]]
    [[ "$output" == *"unexpected sudoers rule for debian in sudoers.d/90-cloud-init-users"* ]]
    [[ "$output" == *"unexpected sudoers rule for root in sudoers.d/90-cloud-init-users"* ]]
    [[ "$output" != *NOPASSWD* ]]
}

@test "a second uid 0 account is CRIT even without a login shell" {
    printf 'toor:x:0:0::/root:/usr/sbin/nologin\n' >> "$ETC_DIR/passwd"
    account_check
    [[ "$output" == CRIT$'\t'"uid 0 account(s): toor" ]]
}

@test "a Defaults line that drops authentication is CRIT" {
    printf 'Defaults !authenticate\n' > "$ETC_DIR/sudoers.d/x"
    account_check
    [[ "$output" == CRIT$'\t'*"Defaults touching authentication in sudoers.d/x"* ]]
}

@test "an include other than the sudoers.d directory is CRIT, also in its old #include spelling" {
    printf '@include /tmp/x\n' >> "$ETC_DIR/sudoers"
    account_check
    [[ "$output" == CRIT$'\t'*"unexpected include in sudoers"* ]]

    common_setup
    printf '#includedir /etc/sudoers.d\n' > "$ETC_DIR/sudoers.d/y"
    account_check
    [[ "$output" == CRIT$'\t'*"unexpected include in sudoers.d/y"* ]]
}

@test "an unreadable sudoers file is WARN" {
    ln -s "$BATS_TEST_TMPDIR/missing" "$ETC_DIR/sudoers.d/dangling"
    account_check
    [[ "$output" == WARN$'\t'"cannot read sudoers.d/dangling" ]]
}

@test "a root key outside the allowlist is CRIT and named by its fingerprint" {
    printf '%s\n' "$TEST_KEY_B" >> "$ROOT_AUTHORIZED_KEYS"
    account_check
    [[ "$output" == CRIT$'\t'"root key(s) outside the allowlist: $TEST_KEY_B_FP" ]]
}

@test "an allowed key with options in front still counts as that key" {
    printf 'from="10.0.0.1" %s\n' "$TEST_KEY_A" > "$ROOT_AUTHORIZED_KEYS"
    account_check
    [[ "$output" == OK$'\t'*"1 root key(s), all allowed" ]]
}

@test "a key line ssh-keygen cannot read is CRIT" {
    printf 'ssh-ed25519 not-a-key garbage\n' >> "$ROOT_AUTHORIZED_KEYS"
    account_check
    [[ "$output" == CRIT$'\t'*"1 unparseable line(s)"* ]]
}

@test "an authorized_keys2 next to root's key file is CRIT" {
    printf '%s\n' "$TEST_KEY_A" > "$(dirname "$ROOT_AUTHORIZED_KEYS")/authorized_keys2"
    account_check
    [[ "$output" == CRIT$'\t'*"authorized_keys2 exists"* ]]
}

@test "no allowlist is WARN" {
    rm "$ETC_DIR/vps-health/root-authorized-keys"
    account_check
    [[ "$output" == WARN$'\t'"no root key allowlist at $ETC_DIR/vps-health/root-authorized-keys" ]]
}

@test "EXPECTED_LOGIN_ACCOUNTS admits a second login account" {
    printf 'deploy:x:1000:1000::/home/deploy:/bin/bash\n' >> "$ETC_DIR/passwd"
    account_check
    [[ "$output" == CRIT$'\t'"unexpected login account(s): deploy" ]]

    export EXPECTED_LOGIN_ACCOUNTS="root deploy"
    account_check
    [[ "$output" == OK$'\t'"login accounts: root deploy;"* ]]
}

@test "--help exits 0 and an unknown option exits 2" {
    account_check --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]

    account_check --bogus
    [ "$status" -eq 2 ]
}
