#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
AM_LOG="$TMP_DIR/am.log"
mkdir -p "$CONFIG_DIR" "$BIN_DIR"
printf 'profile=miui14\nobserve=false\n' > "$CONFIG_DIR/app.conf"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$AM_LOG" > "$BIN_DIR/am"
chmod +x "$BIN_DIR/am"
export PATH="$BIN_DIR:$PATH"

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

[ "$(sh "$TMP_DIR/mipushctl" spoof off)" = 'spoof=off' ]
grep -F -x 'spoof=off' "$CONFIG_DIR/app.conf" >/dev/null
[ "$(sh "$TMP_DIR/mipushctl" mode cut)" = 'pending_mode=cut' ]
[ "$(cat "$CONFIG_DIR/install_mode")" = cut ]

[ "$(sh "$TMP_DIR/mipushctl" enable com.example.app)" = 'enabled com.example.app' ]
grep -F -x 'com.example.app' "$CONFIG_DIR/app.conf" >/dev/null
grep -F -x 'force-stop com.example.app' "$AM_LOG" >/dev/null
[ "$(sh "$TMP_DIR/mipushctl" disable com.example.app)" = 'disabled com.example.app' ]
grep -F -x -- '-com.example.app' "$CONFIG_DIR/app.conf" >/dev/null
[ "$(grep -F -c 'force-stop com.example.app' "$AM_LOG")" = 2 ]

status=$(sh "$TMP_DIR/mipushctl" status)
printf '%s\n' "$status" | grep -F -x 'spoof=off' >/dev/null
printf '%s\n' "$status" | grep -F -x 'profile=miui14' >/dev/null
printf '%s\n' "$status" | grep -F -x 'pending_mode=cut' >/dev/null
printf '%s\n' "$status" | grep -F -x 'reboot_required=true' >/dev/null

if sh "$TMP_DIR/mipushctl" enable 'com.example.app;id' >/dev/null 2>&1; then
    echo 'unsafe package accepted' >&2
    exit 1
fi

if sh "$TMP_DIR/mipushctl" > "$TMP_DIR/usage" 2>&1; then
    echo 'missing command unexpectedly succeeded' >&2
    exit 1
fi
grep -F 'profile [miui14|os4]' "$TMP_DIR/usage" >/dev/null

sh "$TMP_DIR/mipushctl" enable com.other.app >/dev/null
rules=$(sh "$TMP_DIR/mipushctl" apps)
printf '%s\n' "$rules" | grep -F -x -- '-com.example.app' >/dev/null
printf '%s\n' "$rules" | grep -F -x 'com.other.app' >/dev/null
if printf '%s\n' "$rules" | grep -F 'profile=' >/dev/null; then
    echo 'meta key leaked into the rules view' >&2
    exit 1
fi

cat > "$BIN_DIR/cmd" <<'STUB'
#!/bin/sh
printf '%s\n' 'com.aaa.app/.PushReceiver' 'com.bbb.app/.PushReceiver' \
    'com.example.app/.PushReceiver' 'com.zzz.app/.PushReceiver' \
    'com.xiaomi.xmsf/.PushReceiver' 'com.example.app/.SecondReceiver' 'No services found'
STUB
chmod +x "$BIN_DIR/cmd"

scan_out=$(sh "$TMP_DIR/mipushctl" scan)
[ "$(printf '%s\n' "$scan_out" | wc -l)" = 4 ]
printf '%s\n' "$scan_out" | grep -F -x 'com.example.app' >/dev/null
printf '%s\n' "$scan_out" | grep -F -x 'com.zzz.app' >/dev/null
if printf '%s\n' "$scan_out" | grep -F -x 'com.xiaomi.xmsf' >/dev/null; then
    echo 'self package listed as a spoof candidate' >&2
    exit 1
fi
if printf '%s\n' "$scan_out" | grep -F 'No services' >/dev/null; then
    echo 'invalid line leaked into the candidate list' >&2
    exit 1
fi

printf '#!/bin/sh\nexit 0\n' > "$BIN_DIR/cmd"
printf '#!/bin/sh\nif [ "${1:-}" = list ]; then printf "package:com.dump.app\\npackage:com.xiaomi.xmsf\\n"; fi\n' > "$BIN_DIR/pm"
printf '#!/bin/sh\nif [ "${2:-}" = com.dump.app ]; then printf "com.xiaomi.push.service.XMPushService\\n"; fi\n' > "$BIN_DIR/dumpsys"
chmod +x "$BIN_DIR/pm" "$BIN_DIR/dumpsys"

fallback_out=$(sh "$TMP_DIR/mipushctl" scan)
[ "$fallback_out" = 'com.dump.app' ]

echo 'mipushctl tests passed'
