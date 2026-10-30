#!/usr/bin/env bash
# Internal version-axis guard for this module.
#
# The shipped version is injected by the framework build (MIPUSH_ZYGISK_VERSION_NAME /
# MIPUSH_ZYGISK_VERSION_CODE), which means the source defaults in module/Cargo.toml and
# magisk/module.prop are what every local build, every reader of module.prop, and the
# framework-side sync check actually see. Those two files have to agree with each other and
# must never be left on a stale sequence: they were once stuck at v1.0.8/19 while the framework
# had already moved to 1.1.2/21, and the framework-side check skipped the comparison because
# build.sh supports injection.
#
# When the framework axis is supplied (MIPUSH_ZYGISK_VERSION_NAME / _CODE), this script also
# fails when the source defaults lag behind it, so the drift is caught here instead of shipping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CARGO_TOML="$ROOT_DIR/module/Cargo.toml"
MODULE_PROP="$ROOT_DIR/magisk/module.prop"

read_prop_value() {
    sed -nE "s/^$1=(.*)/\1/p" "$MODULE_PROP" | head -n1
}

cargo_version="$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$CARGO_TOML" | head -n1)"
module_version="$(read_prop_value version)"
module_version_name="${module_version#v}"
module_code="$(read_prop_value versionCode)"

fail=0

if [[ -z "$cargo_version" ]]; then
    echo "FAIL: module/Cargo.toml has no version" >&2
    fail=1
fi
if [[ -z "$module_version_name" ]]; then
    echo "FAIL: magisk/module.prop has no version" >&2
    fail=1
fi
if [[ "$cargo_version" != "$module_version_name" ]]; then
    echo "FAIL: version mismatch: Cargo.toml '$cargo_version' vs module.prop '$module_version_name'" >&2
    fail=1
fi
if [[ -z "$module_code" || ! "$module_code" =~ ^[0-9]+$ ]]; then
    echo "FAIL: magisk/module.prop versionCode must be a non-empty integer, got '$module_code'" >&2
    fail=1
fi

if [[ -n "${MIPUSH_ZYGISK_VERSION_NAME:-}" || -n "${MIPUSH_ZYGISK_VERSION_CODE:-}" ]]; then
    if [[ "$cargo_version" != "${MIPUSH_ZYGISK_VERSION_NAME:-}" ]]; then
        echo "FAIL: source default '$cargo_version' lags the framework axis '${MIPUSH_ZYGISK_VERSION_NAME:-}'" >&2
        fail=1
    fi
    if [[ "$module_code" != "${MIPUSH_ZYGISK_VERSION_CODE:-}" ]]; then
        echo "FAIL: source default versionCode '$module_code' lags the framework axis '${MIPUSH_ZYGISK_VERSION_CODE:-}'" >&2
        fail=1
    fi
fi

if (( fail != 0 )); then
    echo "Zygisk version axis check failed." >&2
    exit 1
fi

echo "PASS: Zygisk version axis is consistent (v$module_version_name / $module_code)"
