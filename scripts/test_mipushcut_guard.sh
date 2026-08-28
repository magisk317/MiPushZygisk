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

expect_disabled "image replacement requires mounted xattr support" \
  mipushcut_mark_image_replace "$TMP_DIR/unmounted-content"

echo "mipushcut guard tests passed"
