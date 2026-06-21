#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

find_ndk_home() {
    if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
        printf '%s\n' "${ANDROID_NDK_HOME}"
        return
    fi

    local sdk_roots=(
        "${ANDROID_HOME:-}"
        "${ANDROID_SDK_ROOT:-}"
        "$HOME/development/android-sdk"
        "$HOME/Android/Sdk"
    )

    local root candidate
    for root in "${sdk_roots[@]}"; do
        [[ -n "$root" && -d "$root/ndk" ]] || continue
        candidate="$(find "$root/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
        if [[ -n "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    echo "Android NDK not found. Set ANDROID_NDK_HOME." >&2
    exit 1
}

case "$(uname -s)" in
    Darwin) HOST_TAG="darwin-x86_64" ;;
    Linux) HOST_TAG="linux-x86_64" ;;
    *) echo "Unsupported host OS"; exit 1 ;;
esac

NDK_HOME="$(find_ndk_home)"
TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin"

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOLCHAIN/aarch64-linux-android21-clang"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$TOOLCHAIN/armv7a-linux-androideabi21-clang"
export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$TOOLCHAIN/i686-linux-android21-clang"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$TOOLCHAIN/x86_64-linux-android21-clang"

rm -rf "$PROJECT_ROOT/magisk/zygisk"
mkdir -p "$PROJECT_ROOT/magisk/zygisk"

pushd "$PROJECT_ROOT/module" >/dev/null

build_target() {
    local abi="$1"
    local target="$2"
    echo "==> Building $abi ($target)"
    cargo build --release --target "$target"
    cp "target/$target/release/libmipush_zygisk.so" "$PROJECT_ROOT/magisk/zygisk/$abi.so"
}

build_target "arm64-v8a" "aarch64-linux-android"
build_target "armeabi-v7a" "armv7-linux-androideabi"
build_target "x86" "i686-linux-android"
build_target "x86_64" "x86_64-linux-android"

popd >/dev/null

VERSION_CODE="$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain -- . 2>/dev/null || true)" ]]; then
    VERSION_CODE=$((VERSION_CODE + 1))
fi
VERSION="v0.1($VERSION_CODE)"

sed -e "s/^version=.*/version=$VERSION/" \
    -e "s/^versionCode=.*/versionCode=$VERSION_CODE/" \
    "$PROJECT_ROOT/magisk/module.prop" > "$PROJECT_ROOT/magisk/module.prop.tmp"
mv "$PROJECT_ROOT/magisk/module.prop.tmp" "$PROJECT_ROOT/magisk/module.prop"

rm -rf "$PROJECT_ROOT/build"
mkdir -p "$PROJECT_ROOT/build"

pushd "$PROJECT_ROOT/magisk" >/dev/null
zip -r9 "$PROJECT_ROOT/build/mipush-zygisk-$VERSION.zip" .
popd >/dev/null

echo "==> Done: $PROJECT_ROOT/build/mipush-zygisk-$VERSION.zip"
