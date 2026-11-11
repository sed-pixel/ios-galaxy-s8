#!/bin/bash
# Collect the board facts of a Galaxy S8+ (SM-G955F/FD, dream2lte) from TWRP.
#   collect-facts.sh [OUTDIR]        (default: backup/s8plus-facts)
# Phone in TWRP, USB debugging via adb. READ-ONLY on the phone except for
# copying BOOT and EFS to the PC. The output lands in backup/, which is
# git-ignored: the live DT holds the serial number, EFS holds the IMEI.
set -euo pipefail
out=${1:-backup/s8plus-facts}
mkdir -p "$out"

adb get-state >/dev/null
adb shell getprop ro.product.device        > "$out/product_device.txt" || true
adb shell getprop ro.boot.em.model         > "$out/model.txt"          || true
adb shell cat /proc/cmdline                > "$out/cmdline.txt"
adb shell cat /proc/iomem                  > "$out/iomem.txt"
adb shell cat /proc/cpuinfo                > "$out/cpuinfo.txt"
adb shell cat /sys/class/graphics/fb0/virtual_size > "$out/fb0-size.txt" || true
adb shell 'dmesg | grep -iE "ramoops|pstore"' > "$out/ramoops.txt" || true
adb shell 'ls -l /dev/block/platform/*/by-name/' > "$out/by-name.txt"
adb shell 'for d in /sys/bus/i2c/devices/*; do echo "$d $(cat $d/name 2>/dev/null) $(cat $d/of_node/compatible 2>/dev/null | tr "\0" " ")"; done' \
    > "$out/i2c-devices.txt" || true
adb pull /sys/firmware/fdt "$out/live.dtb" >/dev/null

# Raw copies for recovery. Partition names are resolved from by-name, not
# assumed to be sda7 / sda24 like on the S8.
boot=$(adb shell 'readlink -f /dev/block/platform/*/by-name/BOOT' | tr -d '\r')
efs=$(adb shell 'readlink -f /dev/block/platform/*/by-name/EFS' | tr -d '\r')
echo "BOOT=$boot EFS=$efs" | tee "$out/resolved-partitions.txt"
for pair in "BOOT:$boot" "EFS:$efs"; do
    name=${pair%%:*}; dev=${pair#*:}
    adb shell "dd if=$dev of=/sdcard/$name.img bs=1048576 2>/dev/null; sync"
    adb pull "/sdcard/$name.img" "$out/$name.img" >/dev/null
    adb shell "rm /sdcard/$name.img"
    sha256sum "$out/$name.img" | tee -a "$out/SHA256SUMS"
done
echo "Facts and backups saved in $out"
echo "Next: python3 tools/dream2lte/compare_facts.py $out"
