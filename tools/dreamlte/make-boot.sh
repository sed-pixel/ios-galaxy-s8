#!/bin/bash
# Kernel Mach-O -> Galaxy S8 BOOT image.
#   make-boot.sh KERNEL STOCK_BOOT.img OUT.img [boot-args...]
# Default boot-args: one CPU, verbose console, no watchdog; no root device
# yet, so the first trials end in a root-mount panic by design.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
kernel=$(realpath "$1"); stock=$(realpath "$2"); out=$(realpath -m "$3")
shift 3
# a5touchprobe=0: the A5 touch probe maps Exynos7580 I2C/GPIO; on the S8 its
# first read is a synchronous external abort (boot 8, a5xelte_touch_probe).
args=${*:-debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress wdt=-1 wdt_test=no_user_checkin a5touchprobe=0}
# S8+ (DEVICE=dream2lte): turn on the STM FTS touch driver in the kernel and
# build the loader with its FTS probe, unless the caller chose otherwise.
if [ "${DEVICE:-dreamlte}" = dream2lte ]; then
	[[ " $args " == *" s8fts="* ]] || args="$args s8fts=1"
	export DEVICE
fi
work=$repo/shim/dreamlte/out
mkdir -p "$work"
# The ADT canvas must match the size the kernel presents (SweetFramebuffer).
canvas=1125x2436
[[ " $args " == *" sweetfb_native=1 "* ]] && canvas=1440x2960
# DEVICE=dream2lte selects the Galaxy S8+ identity (unverified on hardware;
# run tools/dream2lte/compare_facts.py on your phone's dump first).
python3 "$repo/tools/mkadt_dreamlte.py" "$work/dreamlte.adt" --canvas "$canvas" --device "${DEVICE:-dreamlte}"
python3 "$repo/tools/mkpayload.py" "$kernel" "$work/dreamlte.adt" "$work/payload.bin" --cmdline "$args"
bash "$repo/shim/dreamlte/build.sh" "$stock" "$work/payload.bin" "$out"
python3 "$repo/tools/dreamlte_bootimg_info.py" "$out" | head -4
