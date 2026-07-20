#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-${CI_COMMIT_TAG:-}}"

if [[ -z "$TAG" ]]; then
    echo "Release tag is required." >&2
    exit 1
fi

read_cargo_version() {
    sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' \
        "$PROJECT_ROOT/module/Cargo.toml" | head -n1
}

read_module_version() {
    sed -nE 's/^version=(.*)/\1/p' "$PROJECT_ROOT/magisk/module.prop" | head -n1
}

cargo_version="$(read_cargo_version)"
module_version="$(read_module_version)"
expected_tag="v$cargo_version"

if [[ -z "$cargo_version" || -z "$module_version" ]]; then
    echo "Failed to resolve Cargo or Magisk module version." >&2
    exit 1
fi

if [[ "$module_version" != "$expected_tag" ]]; then
    echo "Version mismatch: Cargo=$cargo_version, Magisk=$module_version." >&2
    exit 1
fi

if [[ "$TAG" != "$expected_tag" ]]; then
    echo "Tag mismatch: expected $expected_tag, got $TAG." >&2
    exit 1
fi

echo "Release tag verified: $TAG"
