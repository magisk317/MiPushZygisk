#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/magisk/mipushcut_guard.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TARGET="$TMP_DIR/product/app/split-XiaomiServiceFrameworkCN"
mkdir -p "$TARGET"
printf 'stock-xmsf' > "$TARGET/base.apk"

expect_enabled() {
  local name="$1"
  shift
  if ! "$@"; then
    echo "FAIL: expected enabled: $name" >&2
    exit 1
  fi
}

expect_disabled() {
  local name="$1"
  shift
  if "$@"; then
    echo "FAIL: expected disabled: $name" >&2
    exit 1
  fi
}

expect_enabled "stock XMSF path with APK" mipushcut_should_enable "$TARGET"
STATE_FILE="$TMP_DIR/mipushcut.state"
expect_enabled "new install with stock XMSF path" \
  mipushcut_should_enable_with_state "$TARGET" "$STATE_FILE" false

expect_disabled "missing XMSF path" mipushcut_should_enable "$TMP_DIR/product/app/missing"

rm "$TARGET/base.apk"
expect_disabled "XMSF directory without APK" mipushcut_should_enable "$TARGET"

if ! mipushcut_save_state "$STATE_FILE" enabled; then
  echo "FAIL: could not save enabled state" >&2
  exit 1
fi
expect_enabled "enabled state preserves hidden XMSF" \
  mipushcut_should_enable_with_state "$TARGET" "$STATE_FILE" false

if ! mipushcut_save_state "$STATE_FILE" disabled; then
  echo "FAIL: could not save disabled state" >&2
  exit 1
fi
expect_disabled "disabled state remains disabled" \
  mipushcut_should_enable_with_state "$TARGET" "$STATE_FILE" false

rm "$STATE_FILE"
expect_enabled "legacy update preserves old enabled behavior" \
  mipushcut_should_enable_with_state "$TARGET" "$STATE_FILE" true

expect_disabled "config-free first install does not assume legacy MiPushCut" \
  mipushcut_should_enable_with_state "$TARGET" "$STATE_FILE" false

OLD_MODULE_DIR="$TMP_DIR/old-module"
mkdir -p "$OLD_MODULE_DIR/system/product/app/split-XiaomiServiceFrameworkCN"
: > "$OLD_MODULE_DIR/system/product/app/split-XiaomiServiceFrameworkCN/.replace"
expect_enabled "old module marker is detected" \
  mipushcut_has_replace_marker "$OLD_MODULE_DIR"

OLD_PRODUCT_MODULE_DIR="$TMP_DIR/old-product-module"
mkdir -p "$OLD_PRODUCT_MODULE_DIR/product/app/split-XiaomiServiceFrameworkCN"
: > "$OLD_PRODUCT_MODULE_DIR/product/app/split-XiaomiServiceFrameworkCN/.replace"
expect_enabled "legacy product marker is detected" \
  mipushcut_has_replace_marker "$OLD_PRODUCT_MODULE_DIR"

expect_disabled "KernelSU metamodule is absent" \
  mipushcut_has_kernelsu_metamodule "$TMP_DIR/missing-metamodule"

mkdir -p "$TMP_DIR/active-metamodule"
expect_enabled "KernelSU metamodule is present" \
  mipushcut_has_kernelsu_metamodule "$TMP_DIR/active-metamodule"

NESTED_CONTENT="$TMP_DIR/metamodule-content"
mkdir -p "$NESTED_CONTENT/product/product/app/split-XiaomiServiceFrameworkCN"
: > "$NESTED_CONTENT/product/product/app/split-XiaomiServiceFrameworkCN/stale.apk"
expect_enabled "nested product cleanup succeeds" \
  mipushcut_cleanup_nested_product "$NESTED_CONTENT"
expect_disabled "nested product content is removed" \
  test -e "$NESTED_CONTENT/product/product"

mipushcut_mark_image_replace "$TMP_DIR/unmounted-content" && rc=0 || rc=$?
if [ "$rc" -ne 2 ]; then
  echo "FAIL: missing image root must return 2 (in-place metamodule, skip)" >&2
  exit 1
fi

IMAGE_CONTENT="$TMP_DIR/mounted-content"
mkdir -p "$IMAGE_CONTENT"
mipushcut_mark_image_replace "$IMAGE_CONTENT" && rc=0 || rc=$?
if [ "$rc" -eq 2 ]; then
  echo "FAIL: existing image root must not be reported as absent" >&2
  exit 1
fi

echo "mipushcut guard tests passed"

# --- spoof master switch helpers ---

CONF="$TMP_DIR/app.conf"

mipushcut_write_spoof_state "$CONF" off
if [ "$(mipushcut_read_spoof_state "$CONF")" != off ]; then
  echo "FAIL: spoof=off not persisted into a new config" >&2
  exit 1
fi

printf 'profile=miui14\nobserve=false\nair.tv.douyu.android\n' > "$CONF"
mipushcut_write_spoof_state "$CONF" off
if [ "$(mipushcut_read_spoof_state "$CONF")" != off ]; then
  echo "FAIL: spoof=off not patched into an existing config" >&2
  exit 1
fi
grep -q '^profile=miui14$' "$CONF" || { echo "FAIL: profile line clobbered" >&2; exit 1; }
grep -q '^air.tv.douyu.android$' "$CONF" || { echo "FAIL: package lines clobbered" >&2; exit 1; }

mipushcut_write_spoof_state "$CONF" on
if [ "$(mipushcut_read_spoof_state "$CONF")" != on ]; then
  echo "FAIL: spoof=on patch failed" >&2
  exit 1
fi
if [ "$(grep -c 'spoof=' "$CONF")" != 1 ]; then
  echo "FAIL: duplicate spoof lines" >&2
  exit 1
fi

# --- default mode resolution ---

STATE_FILE="$TMP_DIR/mipushcut.state"
rm -f "$STATE_FILE"
printf 'spoof=off\n' >> "$CONF"
mipushcut_save_state "$STATE_FILE" enabled
if [ "$(mipushcut_default_mode "$STATE_FILE" "$CONF")" != cut ]; then
  echo "FAIL: default mode should be cut (enabled + spoof=off)" >&2
  exit 1
fi
mipushcut_write_spoof_state "$CONF" on
if [ "$(mipushcut_default_mode "$STATE_FILE" "$CONF")" != both ]; then
  echo "FAIL: default mode should be both (enabled + spoof=on)" >&2
  exit 1
fi
mipushcut_save_state "$STATE_FILE" disabled
if [ "$(mipushcut_default_mode "$STATE_FILE" "$CONF")" != spoof ]; then
  echo "FAIL: default mode should be spoof (disabled state)" >&2
  exit 1
fi
rm -f "$STATE_FILE"
if [ "$(mipushcut_default_mode "$STATE_FILE" "$CONF")" != both ]; then
  echo "FAIL: default mode should be both on a fresh install" >&2
  exit 1
fi

# --- shared uid 1000 gate ---

PKGLIST="$TMP_DIR/packages.list"
printf 'com.android.systemui 1000 0 /data/user_de/0/com.android.systemui platform:privapp:targetSdkVersion=31:partition=system_ext\n' > "$PKGLIST"
expect_enabled "systemui inside uid 1000 shared user" mipushcut_systemui_shared_uid1000 "$PKGLIST"

printf 'com.android.systemui 10219 0 /data/user_de/0/com.android.systemui platform:privapp:targetSdkVersion=37:partition=system_ext\n' > "$PKGLIST"
expect_disabled "systemui on an isolated uid" mipushcut_systemui_shared_uid1000 "$PKGLIST"

expect_disabled "missing packages.list is not treated as coupled" \
  mipushcut_systemui_shared_uid1000 "$TMP_DIR/missing_packages.list"

# --- choose_mode sets the global selection (KSU capture workaround) ---

rm -f "$STATE_FILE"
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF"
if [ "${MIPUSH_SELECTED_MODE:-}" != both ]; then
  echo "FAIL: choose_mode must set MIPUSH_SELECTED_MODE=both on fresh install (got '${MIPUSH_SELECTED_MODE:-}')" >&2
  exit 1
fi

mipushcut_save_state "$STATE_FILE" disabled
mipushcut_choose_mode "$STATE_FILE" "$CONF"
if [ "$MIPUSH_SELECTED_MODE" != spoof ]; then
  echo "FAIL: choose_mode default should be spoof for a disabled state (got '$MIPUSH_SELECTED_MODE')" >&2
  exit 1
fi

# --- choose_mode defaults follow persisted decisions ---

mipushcut_save_state "$STATE_FILE" enabled
printf 'spoof=off\n' > "$CONF"
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF"
if [ "$MIPUSH_SELECTED_MODE" != cut ]; then
  echo "FAIL: choose_mode default should be cut (enabled + spoof=off)" >&2
  exit 1
fi
rm -f "$STATE_FILE"
mipushcut_write_spoof_state "$CONF" on
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF"
if [ "$MIPUSH_SELECTED_MODE" != both ]; then
  echo "FAIL: choose_mode default should be both on fresh install" >&2
  exit 1
fi


# --- both answers NO aborts the install ---

abort() { exit 1; }
mipushcut_save_state "$STATE_FILE" disabled
printf 'spoof=off\n' >> "$CONF"
( mipushcut_choose_mode "$STATE_FILE" "$CONF" ) 2>/dev/null && {
  echo "FAIL: no/no must abort the install" >&2
  exit 1
}
printf 'spoof=on\n' > "$CONF"


# --- take_key return-code capture regression (Vol+ must register) ---
# Regression for the 2026-10-07 device finding: `take_key 8 || key=$?` only
# captures non-zero returns, so a detected Vol+ (rc=0) fell back to the
# question default. Stub take_key with scripted return codes.

mipushcut_take_key() {
  local mipushcut_stub_rc="${MIPUSHCUT_STUB_SEQ%% *}"
  MIPUSHCUT_STUB_SEQ="${MIPUSHCUT_STUB_SEQ#* }"
  return "$mipushcut_stub_rc"
}

mipushcut_save_state "$STATE_FILE" disabled
mipushcut_write_spoof_state "$CONF" off

# Q1=Vol-, Q2=Vol+ (the exact device failure sequence: no then yes)
MIPUSHCUT_STUB_SEQ="1 0 2"
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF" 2>/dev/null
if [ "${MIPUSH_SELECTED_MODE:-}" != spoof ]; then
  echo "FAIL: Vol- then Vol+ must yield spoof (got '${MIPUSH_SELECTED_MODE:-}')" >&2
  exit 1
fi
echo "PASS: Q1=Vol- Q2=Vol+ -> spoof (rc=0 captured)"

# Q1=Vol+ with cut defaulting to no; Q2=Vol- keeps spoof=no
MIPUSHCUT_STUB_SEQ="0 1 2"
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF" 2>/dev/null
if [ "${MIPUSH_SELECTED_MODE:-}" != cut ]; then
  echo "FAIL: Vol+ then Vol- must yield cut (got '${MIPUSH_SELECTED_MODE:-}')" >&2
  exit 1
fi
echo "PASS: Q1=Vol+ Q2=Vol- -> cut (rc=0 captured on Q1)"

# Both Vol+ on fresh-install defaults
MIPUSHCUT_STUB_SEQ="0 0 2"
unset MIPUSH_SELECTED_MODE
mipushcut_choose_mode "$STATE_FILE" "$CONF" 2>/dev/null
if [ "${MIPUSH_SELECTED_MODE:-}" != both ]; then
  echo "FAIL: Vol+ Vol+ must yield both (got '${MIPUSH_SELECTED_MODE:-}')" >&2
  exit 1
fi
echo "PASS: Q1=Vol+ Q2=Vol+ -> both"

unset -f mipushcut_take_key
echo "take_key rc-capture regression tests passed"
