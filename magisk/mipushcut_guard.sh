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

mipushcut_has_image_replace() {
  mipushcut_content_root="${1:-/data/adb/metamodule/mnt/mipush_zygisk}"
  mipushcut_image_target="$mipushcut_content_root/product/app/split-XiaomiServiceFrameworkCN"

  [ -d "$mipushcut_image_target" ] || return 1
  command -v getfattr >/dev/null 2>&1 || return 1
  [ "$(getfattr -n trusted.overlay.opaque --only-values "$mipushcut_image_target" 2>/dev/null)" = y ]
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
  mipushcut_image_root="${4:-/data/adb/metamodule/mnt/mipush_zygisk}"

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
  if mipushcut_has_image_replace "$mipushcut_image_root"; then
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

# ---------------------------------------------------------------------------
# Installer mode selection and safety gates
# ---------------------------------------------------------------------------

# True when SystemUI runs inside the android.uid.system (uid 1000) shared user.
# On such ROMs (older MIUI/HyperOS ports) hiding the platform-signed stock XMSF
# can flip the shared user's seinfo base to "default", which has no
# seapp_contexts ":complete" entry and makes zygote abort SystemUI forks.
mipushcut_systemui_shared_uid1000() {
  mipushcut_pkg_list="${1:-/data/system/packages.list}"
  [ -r "$mipushcut_pkg_list" ] || return 1
  mipushcut_systemui_uid=$(awk '$1 == "com.android.systemui" { print $2; exit }' "$mipushcut_pkg_list" 2>/dev/null)
  [ "$mipushcut_systemui_uid" = "1000" ]
}

# Read the spoof master switch from app.conf. Absent line defaults to on; the
# XMSF marker prop (mipush.zygisk.enabled) is handled separately and stays on.
mipushcut_read_spoof_state() {
  mipushcut_conf="${1:?}"
  [ -f "$mipushcut_conf" ] || { echo on; return; }
  mipushcut_spoof=$(grep -E '^[[:space:]]*spoof[[:space:]]*=' "$mipushcut_conf" | tail -n 1 | cut -d= -f2 | tr -d '[:space:]')
  [ "$mipushcut_spoof" = off ] && { echo off; return; }
  echo on
}

# Patch the spoof= master switch into app.conf without touching package lines.
mipushcut_write_spoof_state() {
  mipushcut_conf="${1:?}"
  mipushcut_spoof="${2:-on}"
  [ "$mipushcut_spoof" = on ] || mipushcut_spoof=off
  if [ ! -f "$mipushcut_conf" ]; then
    mkdir -p "${mipushcut_conf%/*}" 2>/dev/null || true
    printf '# MiPush Zygisk config\nspoof=%s\n' "$mipushcut_spoof" > "$mipushcut_conf" || return 1
    chmod 600 "$mipushcut_conf" 2>/dev/null || true
    return 0
  fi
  if grep -qE '^[[:space:]]*spoof[[:space:]]*=' "$mipushcut_conf"; then
    sed -i.bak "s|^[[:space:]]*spoof[[:space:]]*=.*|spoof=$mipushcut_spoof|" "$mipushcut_conf" \
      && rm -f "$mipushcut_conf.bak" || return 1
  else
    printf 'spoof=%s\n' "$mipushcut_spoof" >> "$mipushcut_conf" || return 1
  fi
  chmod 600 "$mipushcut_conf" 2>/dev/null || true
  return 0
}

# Default install mode from persisted decisions: both|cut|spoof.
mipushcut_default_mode() {
  if mipushcut_state_is_enabled "${1:-}"; then
    mipushcut_spoof=$(mipushcut_read_spoof_state "${2:-}")
    [ "$mipushcut_spoof" = off ] && { echo cut; return; }
    echo both
    return
  fi
  if mipushcut_state_is_disabled "${1:-}"; then
    echo spoof
    return
  fi
  echo both
}

mipushcut_ui_print() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

# Resolve the install mode without reading input devices. A valid preset is
# written by the root CLI/WebUI; otherwise preserve the previous persisted mode.
mipushcut_preserve_existing_cut() {
  mipushcut_state_is_enabled "${1:-}" || [ "${2:-false}" = true ]
}

mipushcut_choose_mode() {
  local mode_file="${1%/*}/install_mode"
  local preset
  if [ -f "$mode_file" ]; then
    preset=$(tr -d '\r\n' < "$mode_file" 2>/dev/null)
    case "$preset" in
      cut|spoof|both)
        MIPUSH_SELECTED_MODE=$preset
        mipushcut_ui_print "- 预置安装模式 / preset install_mode: $MIPUSH_SELECTED_MODE"
        return 0
        ;;
      *)
        mipushcut_ui_print "- ! 忽略无效 install_mode / invalid preset: $preset"
        ;;
    esac
  fi
  MIPUSH_SELECTED_MODE=$(mipushcut_default_mode "${1:-}" "${2:-}")
  mipushcut_ui_print "- 使用已保存安装模式 / persisted install mode: $MIPUSH_SELECTED_MODE"
}
