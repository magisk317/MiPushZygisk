#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

CONFIG_DIR="$TMP_DIR/config"
mkdir -p "$CONFIG_DIR"
printf 'profile=miui14\nobserve=false\n' > "$CONFIG_DIR/app.conf"

# Run the shipped script against an isolated config path without weakening the
# production default or requiring /data/adb on the CI host.
sed "s|^CONFIG_DIR=.*$|CONFIG_DIR=$CONFIG_DIR|" \
    "$ROOT/magisk/bin/mipushctl" > "$TMP_DIR/mipushctl"
chmod +x "$TMP_DIR/mipushctl"

assert_profile() {
    profile=$1
    output=$(sh "$TMP_DIR/mipushctl" profile "$profile")
    [ "$output" = "profile=$profile" ]
    grep -F -x "profile=$profile" "$CONFIG_DIR/app.conf" >/dev/null
}

assert_rejected() {
    profile=$1
    if sh "$TMP_DIR/mipushctl" profile "$profile" > "$TMP_DIR/output" 2>&1; then
        echo "unsupported profile accepted: $profile" >&2
        exit 1
    fi
    grep -F -x 'miui14 os4' "$TMP_DIR/output" >/dev/null
}

assert_profile os4
assert_profile miui14
assert_rejected hyperos1
assert_rejected legacy-v11

if sh "$TMP_DIR/mipushctl" > "$TMP_DIR/usage" 2>&1; then
    echo "missing command unexpectedly succeeded" >&2
    exit 1
fi
grep -F 'profile [miui14|os4]' "$TMP_DIR/usage" >/dev/null

echo 'mipushctl profile tests passed'
