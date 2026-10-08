#!/system/bin/sh
# Self-heal for MiPushCut. On ROMs where SystemUI shares the android.uid.system
# (uid 1000) shared user with stock XMSF, hiding the platform-signed stock
# package can flip the shared user's seinfo base to "default"; that seinfo has
# no seapp_contexts ":complete" entry and zygote aborts every SystemUI fork.
# After boot, sample SystemUI's persisted seinfo and auto-disable MiPushCut so
# the next boot recovers. Only MiPushCut is rolled back; spoofing stays on.

MODDIR="${0%/*}"
CONFIG_DIR=/data/adb/mipush_zygisk
STATE_FILE=$CONFIG_DIR/mipushcut.state
LOG_FILE=$CONFIG_DIR/mipushcut_selfheal.log
PACKAGES_LIST=/data/system/packages.list

mipushcut_systemui_seinfo() {
  awk '$1 == "com.android.systemui" { print $5; exit }' "$PACKAGES_LIST" 2>/dev/null
}

mipushcut_selfheal() {
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = "enabled" ] || return 0

  mipushcut_waited=0
  while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    [ "$mipushcut_waited" -lt 180 ] || return 0
    sleep 1
    mipushcut_waited=$((mipushcut_waited + 1))
  done

  # packages.list is rewritten by PMS after the boot scan; sample twice so an
  # early stale snapshot cannot mask the flip (a missed detection simply retries
  # on the next boot, the state file stays enabled until a flip is observed).
  sleep 15
  mipushcut_seinfo=$(mipushcut_systemui_seinfo)
  case "$mipushcut_seinfo" in default:*) ;; *) sleep 45 ;; esac
  mipushcut_seinfo=$(mipushcut_systemui_seinfo)
  case "$mipushcut_seinfo" in
    default:*) ;;
    *) return 0 ;;
  esac

  printf 'disabled\n' > "$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
  {
    echo "$(date '+%Y-%m-%d %H:%M:%S') systemui seinfo='$mipushcut_seinfo' (default base); MiPushCut disabled for the next boot"
  } >> "$LOG_FILE"
  chmod 600 "$LOG_FILE" 2>/dev/null || true
  cmd notification post -S bigtext -t "MiPush Zygisk" mipushcut_selfheal \
    "MiPushCut auto-disabled: SystemUI seinfo flipped to default; reboot to recover" \
    >/dev/null 2>&1 || true
}

mipushcut_selfheal &
