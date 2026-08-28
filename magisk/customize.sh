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
else
  mipushcut_should_enable_with_state() { return 1; }
  mipushcut_save_state() { return 1; }
  mipushcut_has_kernelsu_metamodule() { return 1; }
  mipushcut_has_replace_marker() { return 1; }
  mipushcut_cleanup_nested_product() { return 0; }
  mipushcut_mark_image_replace() { return 1; }
fi

if [ "${KSU:-false}" = "true" ]; then
  if ! mipushcut_has_kernelsu_metamodule; then
    if mipushcut_should_enable_with_state \
      "$MIPUSHCUT_TARGET" "$MIPUSHCUT_STATE_FILE" "$PREVIOUS_MIPUSHCUT_REPLACE"; then
      abort "! MiPushCut requires an active KernelSU metamodule. Install meta-overlayfs (or another compatible metamodule), reboot, and retry."
    fi
    REPLACE=''
    rm -rf "$MODPATH/system/product/app/split-XiaomiServiceFrameworkCN"
    rm -f "$MODPATH/product/app/split-XiaomiServiceFrameworkCN/.replace"
    rmdir "$MODPATH/system/product/app" "$MODPATH/system/product" "$MODPATH/system" \
      "$MODPATH/product/app" "$MODPATH/product" 2>/dev/null || true
    ui_print "- MiPushCut skipped: KernelSU metamodule unavailable and stock XMSF is not required"
  else
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

    if mipushcut_should_enable_with_state \
      "$MIPUSHCUT_TARGET" "$MIPUSHCUT_STATE_FILE" "$PREVIOUS_MIPUSHCUT_REPLACE"; then
      # KernelSU normalizes system/product to product after processing REPLACE.
      # Declare the pre-normalization path to avoid product/product nesting.
      REPLACE="$MIPUSHCUT_REPLACE_TARGET"
      rm -f "$MODPATH/system/product/app/split-XiaomiServiceFrameworkCN/.replace" \
        "$MODPATH/product/app/split-XiaomiServiceFrameworkCN/.replace"
      mipushcut_mark_image_replace || \
        abort "! MiPushCut could not mark the meta-overlayfs image replacement target"
      mipushcut_save_state "$MIPUSHCUT_STATE_FILE" enabled || \
        ui_print "- Warning: could not persist MiPushCut enabled state"
      ui_print "- Stock XMSF path/APK or previous state detected; enabling MiPushCut: $MIPUSHCUT_TARGET"
    else
      REPLACE=''
      mipushcut_save_state "$MIPUSHCUT_STATE_FILE" disabled || \
        ui_print "- Warning: could not persist MiPushCut disabled state"
      rm -rf "$MODPATH/system/product/app/split-XiaomiServiceFrameworkCN"
      rm -f "$MODPATH/product/app/split-XiaomiServiceFrameworkCN/.replace"
      rmdir "$MODPATH/system/product/app" "$MODPATH/system/product" "$MODPATH/system" \
        "$MODPATH/product/app" "$MODPATH/product" 2>/dev/null || true
      ui_print "- MiPushCut skipped: stock XMSF path/APK unavailable"
    fi
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
