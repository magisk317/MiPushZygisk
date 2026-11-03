#!/system/bin/sh

rm -f /data/adb/mipush_zygisk/reboot_required

# MiPushCut is handled by the native Magisk/KernelSU REPLACE contract.
# Do not bind-mount the target a second time: duplicate mounts can break
# overlay labels and make unrelated files such as the VINTF manifest unreadable.
exit 0
