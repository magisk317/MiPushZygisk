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

# Wait for a volume key press, following the canonical Volume-Key-Selector
# pattern (Magisk-Modules-Repo/HideNavBar): getevent runs in the background
# writing to a file, the caller polls the file every 0.5s. This keeps the
# installer stdout free and never blocks on a pipe. Returns 0 = Vol+,
# 1 = Vol-, 2 = timeout or no input device (blind install).
# Start the volume-key listener for the whole install (90s). Keys pressed
# while extraction/UI lag is still running must be captured too: KSU install
# output is delayed and reordered, so the user cannot see when a prompt
# window opens - listening must start before anything else.
mipushcut_start_listener() {
  MIPUSHCUT_EVFILE=''
  command -v getevent >/dev/null 2>&1 || { mipushcut_ui_print "- ! getevent 不可用 unavailable"; return 1; }
  command -v timeout >/dev/null 2>&1 || { mipushcut_ui_print "- ! timeout 不可用 unavailable"; return 1; }
  local mipushcut_cand
  for mipushcut_cand in "${TMPDIR:-}" /data/local/tmp /data/adb/mipush_zygisk /tmp; do
    [ -n "$mipushcut_cand" ] || continue
    if : > "$mipushcut_cand/mipushcut_events" 2>/dev/null; then
      MIPUSHCUT_EVFILE="$mipushcut_cand/mipushcut_events"
      break
    fi
  done
  [ -n "$MIPUSHCUT_EVFILE" ] || { mipushcut_ui_print "- ! 无可写事件文件 no writable events file"; return 1; }
  : > "$MIPUSHCUT_EVFILE"
  # Stream the whole window (no -c 1: a stray first event must not end the
  # listener before the volume key arrives).
  # -s KILL: after the install ends the installer cgroup freezes the orphaned
  # listener; a plain SIGTERM is queued but never delivered, so getevent
  # lingered forever. SIGKILL works on frozen processes.
  timeout -s KILL 90 getevent -lq > "$MIPUSHCUT_EVFILE" 2>&1 &
  return 0
}

# Count DOWN occurrences of a key pattern in the event stream. The running
# getevent holds the file open with its own write offset, so truncating the
# file between questions corrupts the stream (new events land after a NUL
# hole). Questions instead diff occurrence counts.
mipushcut_count_keys() {
  local n
  n=$(grep -c "$1" "${MIPUSHCUT_EVFILE:-}" 2>/dev/null)
  [ -n "$n" ] || n=0
  echo "$n"
}

# Wait up to $1 seconds for the next volume key in the stream.
# Returns 0 = Vol+, 1 = Vol-, 2 = nothing captured.
mipushcut_take_key() {
  [ -n "${MIPUSHCUT_EVFILE:-}" ] || return 2
  local base_up="${MIPUSHCUT_BASE_UP:-0}" base_down="${MIPUSHCUT_BASE_DOWN:-0}"
  local count=0 up down
  while [ $count -lt $(($1 * 2)) ]; do
    sleep 0.5
    count=$((count + 1))
    up=$(mipushcut_count_keys 'KEY_VOLUMEUP *DOWN')
    down=$(mipushcut_count_keys 'KEY_VOLUMEDOWN *DOWN')
    [ "$up" -gt "$base_up" ] && return 0
    [ "$down" -gt "$base_down" ] && return 1
  done
  local mipushcut_debug_n
  mipushcut_debug_n=$(wc -l < "${MIPUSHCUT_EVFILE:-}" 2>/dev/null || echo '?')
  mipushcut_ui_print "- ! debug: 未捕获按键 events_lines=$mipushcut_debug_n"
  return 2
}

# Yes/no prompt. Timeout defaults to NO so unattended installs stay safe.
mipushcut_confirm() {
  MIPUSHCUT_BASE_UP=$(mipushcut_count_keys 'KEY_VOLUMEUP *DOWN')
  MIPUSHCUT_BASE_DOWN=$(mipushcut_count_keys 'KEY_VOLUMEDOWN *DOWN')
  mipushcut_ui_print "- 音量+ Vol+ = 是 YES"
  mipushcut_ui_print "- 音量- Vol- = 否 NO"
  mipushcut_ui_print "- 超时 timeout ${1:-10}s = NO"
  mipushcut_take_key "${1:-10}"
  [ "$?" = 0 ]
}

# Interactive install mode picker. Sets the global MIPUSH_SELECTED_MODE to
# cut|spoof|both. KSU install output is not reliably visible while the
# installer blocks (the metamodule delays/reorders customize.sh output), so
# the prompts are two blind yes/no questions with direct key mapping instead
# of a cycling menu:
#   Q1 enable MiPushCut?  Q2 enable device spoof?
#   Vol+ = yes, Vol- = no; no key within the window keeps the question's
#   default, which mirrors the previous install's persisted decision.
# /data/adb/mipush_zygisk/install_mode (cut|spoof|both) overrides both
# prompts and skips the interaction entirely.
mipushcut_choose_mode() {
  MIPUSH_SELECTED_MODE=both
  local mipushcut_mode_file="${1%/*}/install_mode"
  if [ -f "$mipushcut_mode_file" ]; then
    local mipushcut_preset
    mipushcut_preset=$(cat "$mipushcut_mode_file" 2>/dev/null)
    case "$mipushcut_preset" in
      cut|spoof|both)
        MIPUSH_SELECTED_MODE=$mipushcut_preset
        mipushcut_ui_print "- 预置模式 preset install_mode: $MIPUSH_SELECTED_MODE"
        return 0
        ;;
    esac
  fi

  local mipushcut_cut=yes mipushcut_spoof=yes
  if mipushcut_state_is_disabled "${1:-}"; then
    mipushcut_cut=no
  fi
  if [ "$(mipushcut_read_spoof_state "${2:-}")" = off ]; then
    mipushcut_spoof=no
  fi

  mipushcut_ui_print "- ========= 模式选择 mode ========="

  mipushcut_ui_print "- Q1: 启用精简 MiPushCut?"
  mipushcut_ui_print "-  (隐藏 stock XMSF)"
  mipushcut_ui_print "- 音量+ Vol+ = 是 YES"
  mipushcut_ui_print "- 音量- Vol- = 否 NO"
  mipushcut_ui_print "- 无按键 no key = $mipushcut_cut"
  mipushcut_ui_print "- (8s)"
  MIPUSHCUT_BASE_UP=0
  MIPUSHCUT_BASE_DOWN=0
  # take_key returns 0 (Vol+) / 1 (Vol-) / 2 (timeout). A plain `cmd || key=$?`
  # only captures non-zero returns, so a detected Vol+ silently fell back to
  # the question default. Capture all three return codes explicitly.
  if mipushcut_take_key 8; then
    mipushcut_key=0
  else
    mipushcut_key=$?
  fi
  [ "$mipushcut_key" = 1 ] && mipushcut_cut=no
  [ "$mipushcut_key" = 0 ] && mipushcut_cut=yes
  # Q2 diffs against the counts as of now: only NEW presses count.
  MIPUSHCUT_BASE_UP=$(mipushcut_count_keys 'KEY_VOLUMEUP *DOWN')
  MIPUSHCUT_BASE_DOWN=$(mipushcut_count_keys 'KEY_VOLUMEDOWN *DOWN')
  mipushcut_ui_print "- -> MiPushCut: $mipushcut_cut"

  mipushcut_ui_print "- Q2: 启用伪装 device spoof?"
  mipushcut_ui_print "- 音量+ Vol+ = 是 YES"
  mipushcut_ui_print "- 音量- Vol- = 否 NO"
  mipushcut_ui_print "- 无按键 no key = $mipushcut_spoof"
  mipushcut_ui_print "- (8s)"
  # take_key returns 0 (Vol+) / 1 (Vol-) / 2 (timeout). A plain `cmd || key=$?`
  # only captures non-zero returns, so a detected Vol+ silently fell back to
  # the question default. Capture all three return codes explicitly.
  if mipushcut_take_key 8; then
    mipushcut_key=0
  else
    mipushcut_key=$?
  fi
  [ "$mipushcut_key" = 1 ] && mipushcut_spoof=no
  [ "$mipushcut_key" = 0 ] && mipushcut_spoof=yes
  mipushcut_ui_print "- -> spoof: $mipushcut_spoof"

  if [ "$mipushcut_cut" = no ] && [ "$mipushcut_spoof" = no ]; then
    # Both answers NO = nothing enabled: abort instead of silently installing
    # a module that does nothing (the picker default must not leak through).
    abort "! 精简与伪装均未选择 / both MiPushCut and spoof answered NO - nothing to install. 重刷 reflash 并至少启用一项."
  fi
  if [ "$mipushcut_cut" = yes ] && [ "$mipushcut_spoof" = yes ]; then
    MIPUSH_SELECTED_MODE=both
  elif [ "$mipushcut_cut" = yes ]; then
    MIPUSH_SELECTED_MODE=cut
  elif [ "$mipushcut_spoof" = yes ]; then
    MIPUSH_SELECTED_MODE=spoof
  fi
  mipushcut_ui_print "- ========= 结果 result ========="
  mipushcut_ui_print "- 精简 cut: $mipushcut_cut"
  mipushcut_ui_print "- 伪装 spoof: $mipushcut_spoof"
  mipushcut_ui_print "- 已选模式 mode: $MIPUSH_SELECTED_MODE"
}
