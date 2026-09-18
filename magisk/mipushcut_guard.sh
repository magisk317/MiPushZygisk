#!/system/bin/sh

# MiPushCut is enabled only when the stock Xiaomi Service Framework directory
# and at least one APK are present. Do not infer the decision from mutable
# device or ROM properties: users and custom ROMs may spoof those values.

mipushcut_has_stock_xmsf() {
  mipushcut_target="${1:-/product/app/split-XiaomiServiceFrameworkCN}"

  [ -d "$mipushcut_target" ] || return 1
  find "$mipushcut_target" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null \
    | grep -q .
}

mipushcut_state_is_enabled() {
  [ -f "$1" ] \
    && grep -F -x -q enabled "$1"
}

mipushcut_state_is_disabled() {
  [ -f "$1" ] \
    && grep -F -x -q disabled "$1"
}

mipushcut_has_replace_marker() {
  mipushcut_module_path="$1"

  [ -f "$mipushcut_module_path/system/product/app/split-XiaomiServiceFrameworkCN/.replace" ] \
    || [ -f "$mipushcut_module_path/product/app/split-XiaomiServiceFrameworkCN/.replace" ]
}

mipushcut_has_kernelsu_metamodule() {
  mipushcut_metamodule_path="${1:-/data/adb/metamodule}"

  [ -e "$mipushcut_metamodule_path" ] || [ -L "$mipushcut_metamodule_path" ]
}

mipushcut_cleanup_nested_product() {
  mipushcut_content_root="${1:-/data/adb/metamodule/mnt/mipush_zygisk}"
  mipushcut_nested_product="$mipushcut_content_root/product/product"

  [ -d "$mipushcut_nested_product" ] || return 0
  rm -rf "$mipushcut_nested_product"
}

# Pre-mark the replacement target inside a metamodule image root.
#
# Only metamodules that relocate module content into a mounted image (such as
# meta-overlayfs) expose /data/adb/metamodule/mnt/<module>. Metamodules that
# mount module directories in place (such as meta-magic_mount-rs) have no such
# root; for them the REPLACE marker applied by the installer's mark_replace is
# the only mechanism and pre-marking must not be treated as a failure.
#
# Return codes:
#   0 - image root present and the target was marked opaque
#   1 - image root present but marking failed (broken xattr support)
#   2 - no image root: in-place metamodule, nothing to pre-mark
mipushcut_mark_image_replace() {
  mipushcut_content_root="${1:-/data/adb/metamodule/mnt/mipush_zygisk}"
  mipushcut_image_target="$mipushcut_content_root/product/app/split-XiaomiServiceFrameworkCN"

  [ -d "$mipushcut_content_root" ] || return 2
  mkdir -p "$mipushcut_image_target" || return 1
  command -v setfattr >/dev/null 2>&1 || return 1
  setfattr -n trusted.overlay.opaque -v y "$mipushcut_image_target"
}

mipushcut_should_enable_with_state() {
  mipushcut_previous_replace="${3:-false}"

  # Preserve an explicit previous decision during module updates. The old
  # replacement may make the real product path temporarily invisible.
  if mipushcut_state_is_enabled "${2:-/data/adb/mipush_zygisk/mipushcut.state}"; then
    return 0
  fi
  if mipushcut_state_is_disabled "${2:-/data/adb/mipush_zygisk/mipushcut.state}"; then
    return 1
  fi

  # Releases before persistent state recorded the decision in the module's
  # .replace marker. The installer captures that marker before replacing the
  # old module directory.
  if [ "$mipushcut_previous_replace" = "true" ]; then
    return 0
  fi

  mipushcut_has_stock_xmsf "${1:-/product/app/split-XiaomiServiceFrameworkCN}"
}

mipushcut_save_state() {
  mipushcut_state_file="$1"
  mipushcut_state="$2"
  case "$mipushcut_state_file" in
    */*) mipushcut_state_dir="${mipushcut_state_file%/*}" ;;
    *) mipushcut_state_dir=. ;;
  esac
  mipushcut_tmp_file="$mipushcut_state_file.tmp.$$"

  mkdir -p "$mipushcut_state_dir" || return 1
  printf '%s\n' "$mipushcut_state" > "$mipushcut_tmp_file" || return 1
  chmod 600 "$mipushcut_tmp_file" 2>/dev/null || true
  mv -f "$mipushcut_tmp_file" "$mipushcut_state_file"
}

mipushcut_should_enable() {
  mipushcut_has_stock_xmsf "${1:-/product/app/split-XiaomiServiceFrameworkCN}"
}
