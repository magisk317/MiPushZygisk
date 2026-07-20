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
    cargo build --locked --release --target "$target"
    cp "target/$target/release/libmipush_zygisk.so" "$PROJECT_ROOT/magisk/zygisk/$abi.so"
}

build_target "arm64-v8a" "aarch64-linux-android"
build_target "armeabi-v7a" "armv7-linux-androideabi"
build_target "x86" "i686-linux-android"
build_target "x86_64" "x86_64-linux-android"

popd >/dev/null

read_cargo_version() {
    sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' \
        "$PROJECT_ROOT/module/Cargo.toml" | head -n1
}

read_module_prop_value() {
    local key="$1"
    sed -nE "s/^${key}=(.*)/\1/p" "$PROJECT_ROOT/magisk/module.prop" | head -n1
}

VERSION_NAME="${MIPUSH_ZYGISK_VERSION_NAME:-$(read_cargo_version)}"
if [[ -z "$VERSION_NAME" ]]; then
    VERSION_NAME="$(read_module_prop_value version | sed -E 's/^v//; s/\([0-9]+\)$//')"
fi
if [[ -z "$VERSION_NAME" ]]; then
    echo "Failed to resolve version name. Set MIPUSH_ZYGISK_VERSION_NAME." >&2
    exit 1
fi
VERSION_NAME="${VERSION_NAME#v}"

normalize_build_timestamp() {
    local raw="$1"
    local compact="${raw//[^0-9]/}"
    [[ "${#compact}" -eq 14 ]] || return 1
    printf '%s_%s\n' "${compact:0:8}" "${compact:8:6}"
}

if [[ -n "${MAGISK_BUILD_TIMESTAMP:-}" ]]; then
    if BUILD_TIMESTAMP="$(normalize_build_timestamp "$MAGISK_BUILD_TIMESTAMP")"; then
        VERSION_NAME="${VERSION_NAME}-${BUILD_TIMESTAMP}"
    else
        echo "Invalid MAGISK_BUILD_TIMESTAMP: $MAGISK_BUILD_TIMESTAMP" >&2
        exit 1
    fi
fi

VERSION_CODE="${MIPUSH_ZYGISK_VERSION_CODE:-$(read_module_prop_value versionCode)}"
if [[ -z "$VERSION_CODE" ]]; then
    VERSION_CODE=1
fi
if [[ ! "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
    echo "Invalid version code: $VERSION_CODE" >&2
    exit 1
fi

VERSION="v$VERSION_NAME"
BUILD_TYPE="${MAGISK_BUILD_TYPE:-release}"
if [[ "$BUILD_TYPE" != "debug" && "$BUILD_TYPE" != "release" ]]; then
    echo "Invalid MAGISK_BUILD_TYPE: $BUILD_TYPE" >&2
    exit 1
fi

rm -rf "$PROJECT_ROOT/build"
mkdir -p "$PROJECT_ROOT/build"

package_abi() {
    local abi="$1"
    local is_universal="$2"
    
    local artifact_name
    if [[ "$is_universal" == "true" ]]; then
        artifact_name="universal_MiPushZygisk_${VERSION}_${BUILD_TYPE}.zip"
    else
        artifact_name="${abi}_MiPushZygisk_${VERSION}_${BUILD_TYPE}.zip"
    fi

    local stage_dir="$PROJECT_ROOT/build/stage_${abi:-universal}"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    
    cp -r "$PROJECT_ROOT/magisk/"* "$stage_dir/"
    sed -e "s/^version=.*/version=$VERSION/" \
        -e "s/^versionCode=.*/versionCode=$VERSION_CODE/" \
        "$stage_dir/module.prop" > "$stage_dir/module.prop.tmp"
    mv "$stage_dir/module.prop.tmp" "$stage_dir/module.prop"
    
    if [[ "$is_universal" == "false" ]]; then
        # Remove all other ABIs from zygisk folder
        find "$stage_dir/zygisk" -mindepth 1 -maxdepth 1 -type f ! -name "${abi}.so" -delete
    fi
    
    pushd "$stage_dir" >/dev/null
    zip -r9 "$PROJECT_ROOT/build/$artifact_name" . >/dev/null
    popd >/dev/null
    
    echo "==> Created: $PROJECT_ROOT/build/$artifact_name"
}

package_abi "universal" "true"
package_abi "arm64-v8a" "false"
package_abi "armeabi-v7a" "false"
package_abi "x86" "false"
package_abi "x86_64" "false"

# Cleanup staging directories
rm -rf "$PROJECT_ROOT/build"/stage_*
