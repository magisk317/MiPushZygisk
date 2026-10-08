# KernelSU sources this file after extracting the module and provides KSU=true.
# Magisk uses the dedicated installer loaded by update-binary. KernelSU needs an
# active metamodule before a system replacement can be requested.

CONFIG_DIR=/data/adb/mipush_zygisk
CONFIG_FILE=$CONFIG_DIR/app.conf
DEVICE_CONFIG_FILE=$CONFIG_DIR/device.conf
DEFAULT_CONFIG=$MODPATH/defaults/app.conf
DEFAULT_DEVICE_CONFIG=$MODPATH/defaults/device.conf
MIPUSHCUT_TARGET=/product/app/split-XiaomiServiceFrameworkCN
MIPUSHCUT_REPLACE_TARGET=/system/product/app/split-XiaomiServiceFrameworkCN
MIPUSHCUT_STATE_FILE=$CONFIG_DIR/mipushcut.state
PREVIOUS_MIPUSHCUT_REPLACE=false
REPLACE=''

if [ -r "$MODPATH/mipushcut_guard.sh" ]; then
  . "$MODPATH/mipushcut_guard.sh"
  # Listen from the very first line: presses during the (UI-lagged)
  # extraction phase must be captured for the mode prompts.
  mipushcut_start_listener
else
  mipushcut_should_enable_with_state() { return 1; }
  mipushcut_save_state() { return 1; }
  mipushcut_has_kernelsu_metamodule() { return 1; }
  mipushcut_has_replace_marker() { return 1; }
  mipushcut_cleanup_nested_product() { return 0; }
  mipushcut_mark_image_replace() { return 2; }
  mipushcut_choose_mode() { MIPUSH_SELECTED_MODE=both; }
  mipushcut_systemui_shared_uid1000() { return 1; }
  mipushcut_confirm() { return 1; }
  mipushcut_write_spoof_state() { return 0; }
fi

# The picker sets MIPUSH_SELECTED_MODE globally: command substitution does
# not reliably capture function stdout in the KSU installer environment.
mipushcut_choose_mode "$MIPUSHCUT_STATE_FILE" "$CONFIG_FILE"
MODE=$MIPUSH_SELECTED_MODE
MIPUSHCUT_WANTED=false
case "$MODE" in cut|both) MIPUSHCUT_WANTED=true ;; esac

if [ "${KSU:-false}" = "true" ]; then
  if [ "$MIPUSHCUT_WANTED" = true ] && ! mipushcut_has_kernelsu_metamodule; then
    abort "! MiPushCut 需要已激活的 KernelSU 变形模块 / MiPushCut requires an active KernelSU metamodule. Install meta-overlayfs first, reboot and retry."
  fi

  if [ "$MIPUSHCUT_WANTED" = true ]; then
    mipushcut_cleanup_nested_product || \
      ui_print "- Warning: could not clean legacy nested product content"

    for previous_module_path in \
      "/data/adb/modules/mipush_zygisk" \
      "/data/adb/modules_update/mipush_zygisk"; do
      [ "$previous_module_path" = "${MODPATH:-}" ] && continue
      if mipushcut_has_replace_marker "$previous_module_path"; then
        PREVIOUS_MIPUSHCUT_REPLACE=true
        break
      fi
    done

    if ! mipushcut_should_enable_with_state \
      "$MIPUSHCUT_TARGET" "$MIPUSHCUT_STATE_FILE" "$PREVIOUS_MIPUSHCUT_REPLACE"; then
      ui_print "- MiPushCut 跳过: stock XMSF 路径/APK 不存在 / skipped: stock XMSF path unavailable"
      MIPUSHCUT_WANTED=false
    elif mipushcut_systemui_shared_uid1000; then
      # Safety gate: on ROMs where SystemUI shares uid 1000 with stock XMSF
      # (older MIUI/HyperOS ports), hiding the platform-signed stock package can
      # flip the shared user's seinfo and crash-loop SystemUI. Require explicit
      # consent; unattended installs skip MiPushCut instead.
      ui_print "! 警告: 此 ROM 的 SystemUI 与 stock XMSF 同在 uid 1000 共享用户 / WARNING: SystemUI shares the uid 1000 shared user."
      ui_print "! 隐藏 stock XMSF 可能翻转共享用户 seinfo 并导致 SystemUI 崩溃 / hiding stock XMSF may crash SystemUI."
      if mipushcut_confirm 15; then
        ui_print "! 已按要求启用 MiPushCut; 若 SystemUI seinfo 翻转, 开机自愈将自动禁用 / enabled at your request; boot self-heal will auto-disable it."
      else
        ui_print "- 共享组安全门禁拦截, MiPushCut 已跳过 (伪装仍生效) / skipped by the shared-uid safety gate"
        MIPUSHCUT_WANTED=false
      fi
    fi
  fi

  if [ "$MIPUSHCUT_WANTED" = true ]; then
    # KernelSU normalizes system/product to product after processing REPLACE.
    # Declare the pre-normalization path to avoid product/product nesting.
    REPLACE="$MIPUSHCUT_REPLACE_TARGET"
    rm -f "$MODPATH/system/product/app/split-XiaomiServiceFrameworkCN/.replace" \
      "$MODPATH/product/app/split-XiaomiServiceFrameworkCN/.replace"
    mipushcut_mark_image_replace && mipushcut_mark_status=0 || mipushcut_mark_status=$?
    if [ "$mipushcut_mark_status" -eq 2 ]; then
      ui_print "- MiPushCut: in-place metamodule detected; REPLACE marker is applied by the metamodule installer"
    elif [ "$mipushcut_mark_status" -ne 0 ]; then
      abort "! MiPushCut could not mark the meta-overlayfs image replacement target"
    fi
    mipushcut_save_state "$MIPUSHCUT_STATE_FILE" enabled || \
      ui_print "- Warning: could not persist MiPushCut enabled state"
    ui_print "- MiPushCut 已启用 / enabled: $MIPUSHCUT_TARGET"
  else
    REPLACE=''
    mipushcut_save_state "$MIPUSHCUT_STATE_FILE" disabled || \
      ui_print "- Warning: could not persist MiPushCut disabled state"
    rm -rf "$MODPATH/system/product/app/split-XiaomiServiceFrameworkCN"
    rm -f "$MODPATH/product/app/split-XiaomiServiceFrameworkCN/.replace"
    rmdir "$MODPATH/system/product/app" "$MODPATH/system/product" "$MODPATH/system" \
      "$MODPATH/product/app" "$MODPATH/product" 2>/dev/null || true
    [ "$MODE" = spoof ] && ui_print "- 只伪装模式: stock XMSF 未改动 / spoof-only: stock XMSF untouched"
  fi
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ] && [ -f "$DEFAULT_CONFIG" ]; then
  cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
fi

if [ ! -f "$DEVICE_CONFIG_FILE" ] && [ -f "$DEFAULT_DEVICE_CONFIG" ]; then
  cp "$DEFAULT_DEVICE_CONFIG" "$DEVICE_CONFIG_FILE"
  chmod 600 "$DEVICE_CONFIG_FILE"
fi

# Spoof master switch follows the selected mode; cut-only disables spoofing.
case "$MODE" in
  cut) mipushcut_write_spoof_state "$CONFIG_FILE" off || \
    ui_print "- Warning: could not persist spoof=off" ;;
  *) mipushcut_write_spoof_state "$CONFIG_FILE" on || \
    ui_print "- Warning: could not persist spoof=on" ;;
esac
