#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi
if [[ -d "/usr/local/cargo/bin" ]]; then
    export PATH="/usr/local/cargo/bin:$PATH"
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

ALL_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)
SKIP_BUILD="${MIPUSH_ZYGISK_SKIP_BUILD:-false}"
BUILD_ABIS=()
if [[ "$SKIP_BUILD" != "true" ]]; then
    read -r -a BUILD_ABIS <<< "${MIPUSH_ZYGISK_BUILD_ABIS:-${ALL_ABIS[*]}}"
    if [[ "${#BUILD_ABIS[@]}" -eq 0 ]]; then
        echo "MIPUSH_ZYGISK_BUILD_ABIS must select at least one ABI." >&2
        exit 1
    fi
fi

validate_abis() {
    local abi supported candidate
    for abi in "$@"; do
        supported=false
        for candidate in "${ALL_ABIS[@]}"; do
            if [[ "$abi" == "$candidate" ]]; then
                supported=true
                break
            fi
        done
        if [[ "$supported" != "true" ]]; then
            echo "Unsupported Android ABI: $abi" >&2
            exit 1
        fi
    done
}

validate_abis "${BUILD_ABIS[@]}"

configure_linkers() {
    local ndk_home="$1"
    local host_os host_arch host_tag toolchain linker
    host_os="$(uname -s)"
    host_arch="$(uname -m)"

    case "$host_os:$host_arch" in
        Linux:aarch64|Linux:arm64)
            local abi prebuilt_root sysroot resource_dir common_rustflags
            for abi in "${BUILD_ABIS[@]}"; do
                case "$abi" in
                    arm64-v8a|armeabi-v7a) ;;
                    *)
                        echo "Linux ARM64 hosts only build ARM ABIs; requested $abi." >&2
                        exit 1
                        ;;
                esac
            done
            prebuilt_root="$ndk_home/toolchains/llvm/prebuilt/linux-x86_64"
            sysroot="$prebuilt_root/sysroot"
            resource_dir="$(find "$prebuilt_root/lib/clang" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
            if [[ ! -d "$sysroot" || ! -d "$resource_dir" ]]; then
                echo "Android NDK sysroot or Clang resource directory is missing." >&2
                exit 1
            fi
            command -v clang >/dev/null 2>&1 || {
                echo "Native clang is required on Linux ARM64 hosts." >&2
                exit 1
            }
            command -v ld.lld >/dev/null 2>&1 || {
                echo "Native lld is required on Linux ARM64 hosts." >&2
                exit 1
            }
            common_rustflags="-C link-arg=--sysroot=$sysroot -C link-arg=-resource-dir=$resource_dir -C link-arg=-fuse-ld=lld"
            export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=clang
            export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=--target=aarch64-linux-android21 $common_rustflags"
            export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER=clang
            export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_RUSTFLAGS="-C link-arg=--target=armv7a-linux-androideabi21 $common_rustflags"
            ;;
        Linux:x86_64|Linux:amd64)
            host_tag="linux-x86_64"
            toolchain="$ndk_home/toolchains/llvm/prebuilt/$host_tag/bin"
            export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android21-clang"
            export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$toolchain/armv7a-linux-androideabi21-clang"
            export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$toolchain/i686-linux-android21-clang"
            export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$toolchain/x86_64-linux-android21-clang"
            ;;
        Darwin:x86_64|Darwin:arm64)
            host_tag="darwin-x86_64"
            toolchain="$ndk_home/toolchains/llvm/prebuilt/$host_tag/bin"
            export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android21-clang"
            export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$toolchain/armv7a-linux-androideabi21-clang"
            export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$toolchain/i686-linux-android21-clang"
            export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$toolchain/x86_64-linux-android21-clang"
            ;;
        *)
            echo "Unsupported build host: $host_os $host_arch" >&2
            exit 1
            ;;
    esac

    for linker in \
        "${CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER:-}" \
        "${CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER:-}" \
        "${CARGO_TARGET_I686_LINUX_ANDROID_LINKER:-}" \
        "${CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER:-}"; do
        [[ -z "$linker" || "$linker" == "clang" || -x "$linker" ]] || {
            echo "Android NDK linker is missing: $linker" >&2
            exit 1
        }
    done
}

build_target() {
    local abi="$1" target
    case "$abi" in
        arm64-v8a) target="aarch64-linux-android" ;;
        armeabi-v7a) target="armv7-linux-androideabi" ;;
        x86) target="i686-linux-android" ;;
        x86_64) target="x86_64-linux-android" ;;
        *) echo "Unsupported Android ABI: $abi" >&2; exit 1 ;;
    esac
    echo "==> Building $abi ($target)"
    cargo build --locked --release --target "$target"
    cp "target/$target/release/libmipush_zygisk.so" "$PROJECT_ROOT/magisk/zygisk/$abi.so"
}

if [[ "$SKIP_BUILD" != "true" ]]; then
    NDK_HOME="$(find_ndk_home)"
    configure_linkers "$NDK_HOME"
    rm -rf "$PROJECT_ROOT/magisk/zygisk"
    mkdir -p "$PROJECT_ROOT/magisk/zygisk"
    pushd "$PROJECT_ROOT/module" >/dev/null
    for abi in "${BUILD_ABIS[@]}"; do
        build_target "$abi"
    done
    popd >/dev/null
fi

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

    local stage_dir="$PROJECT_ROOT/build/stage_${abi}"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"

    # Preserve dotfiles such as system/.../.replace in the module payload.
    cp -a "$PROJECT_ROOT/magisk/." "$stage_dir/"
    # KernelSU treats a root-level install.sh as a legacy installer and skips
    # its standard customize.sh/REPLACE flow. Keep this installer available to
    # the custom Magisk update-binary under a manager-specific name instead.
    mv "$stage_dir/install.sh" "$stage_dir/magisk-install.sh"
    sed -e "s/^version=.*/version=$VERSION/" \
        -e "s/^versionCode=.*/versionCode=$VERSION_CODE/" \
        "$stage_dir/module.prop" > "$stage_dir/module.prop.tmp"
    mv "$stage_dir/module.prop.tmp" "$stage_dir/module.prop"

    if [[ "$is_universal" == "false" ]]; then
        find "$stage_dir/zygisk" -mindepth 1 -maxdepth 1 -type f ! -name "${abi}.so" -delete
    fi

    pushd "$stage_dir" >/dev/null
    zip -r9 "$PROJECT_ROOT/build/$artifact_name" . >/dev/null
    popd >/dev/null

    echo "==> Created: $PROJECT_ROOT/build/$artifact_name"
}

for abi in "${BUILD_ABIS[@]}"; do
    package_abi "$abi" false
done

package_universal="${MIPUSH_ZYGISK_PACKAGE_UNIVERSAL:-auto}"
if [[ "$package_universal" != "true" && "$package_universal" != "false" && "$package_universal" != "auto" ]]; then
    echo "MIPUSH_ZYGISK_PACKAGE_UNIVERSAL must be true, false, or auto." >&2
    exit 1
fi
all_abis_present=true
for abi in "${ALL_ABIS[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/magisk/zygisk/$abi.so" ]]; then
        all_abis_present=false
        break
    fi
done
if [[ "$package_universal" == "true" && "$all_abis_present" != "true" ]]; then
    echo "Cannot package a universal module until all ABI libraries are present." >&2
    exit 1
fi
if [[ "$package_universal" == "true" || ( "$package_universal" == "auto" && "$all_abis_present" == "true" ) ]]; then
    package_abi universal true
fi

# Cleanup staging directories
rm -rf "$PROJECT_ROOT/build"/stage_*
