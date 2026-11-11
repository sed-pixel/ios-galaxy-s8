# iOS on the Galaxy S8+ (SM-G955F / G955FD, dream2lte): UNTESTED DRAFT

> ⚠️ **Nobody has booted this on an S8+.** The S8 port (`s8-install.md`) is the base. Facts below were read from a real SM-G955FD in TWRP (2026-11-11); the code changes are built and unit-tested on a PC only. Expect several failed boots. Installing the iOS root **erases USERDATA** (all Android data) and the bootloader is already tripped on phones set up for custom ROMs. Same limits as the S8: very slow (CPU rendering), no Wi-Fi, audio, camera or battery readout, security off.

Exynos **SM-G955F / G955FD** only. The Snapdragon S8+ models (G955U/W/0) cannot run this.

## What was measured on the S8+ (read-only, from TWRP)

| Item | S8+ value | vs. the S8 code |
| --- | --- | --- |
| Board / SoC | `dream2lte`, `samsungexynos8895` | same SoC |
| S-Boot framebuffer | `0xcc000000`, 1440×2960 (fb0 virtual 1440×5920 = two buffers) | same |
| RAM banks | `80000000-bc7fffff`, `c0000000-ffffffff`, `880000000-8ffffffff`, nothing reserved in the high bank | same |
| GIC | node `interrupt-controller@10200000` (S8 code: GICD `0x10201000`, GICC `0x10202000`, i.e. +0x1000/+0x2000) | consistent, not read register-by-register |
| UFS / DECON / SPEEDY / touch bus | `11120000` / `12860000` / `15b50000` / `108e0000` | same |
| TWRP ramoops | `0x92000000` | same base |
| BOOT partition | `sda7` | same |
| **USERDATA partition** | **`sda27`** (`sda24` is `CP_DEBUG`) | **differs** (S8: `sda24`) |
| PMIC / fuel gauge | `s2mps17mfd`, `max77865` | same |
| **Touch chip** | **STMicroelectronics FTS8CD56**, `stm,fts_touch`, i2c-5 address **0x49**, IRQ gpa1-0, rails LDO34 1.85 V + LDO35 3.3 V, range 1440×2960 | **differs** (S8: Samsung S6SY761 at 0x48) |

`sda24` is wrong on this phone. Never paste an S8 command that names it. The loader, kernel and `flash-chunks.ps1` find USERDATA by name, and `pull-sweetlog.ps1` was changed to do the same.

## 1. Collect facts and back up (phone in TWRP)

```bash
bash tools/dream2lte/collect-facts.sh        # saves to backup/s8plus-facts (git-ignored)
python3 tools/dream2lte/compare_facts.py backup/s8plus-facts
```

Read-only on the phone; it copies **BOOT and EFS** (IMEI data: keep private, never commit) to your PC. Also make a full TWRP backup of Boot, EFS, System and Data. `compare_facts.py` prints MATCH / NOTE / DIFF / UNKNOWN per fact. The expected result is the table above: all MATCH plus two NOTEs (partition number, touch chip).

## 2. Build

Follow `s8-install.md` steps 2 and 3 (XNU kernel on GitHub Actions, iOS root from the iPhone X 16.7.16 IPSW you download yourself). The kernel must be built **with `xnu/patches/0124-dreamlte-s8.patch` as updated here**: it carries the S8+ touch driver.

BOOT image, using **your own S8+ stock BOOT**:

```bash
DEVICE=dream2lte bash tools/dreamlte/make-boot.sh xnu/out/kernel.development.a5xelte \
  backup/s8plus-facts/BOOT.img s8plus-ios-boot.img \
  debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 ufsroot=USERDATA \
  unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 \
  launchd_unsecure_cache=1 wdt=-1 a5touchprobe=0 a5fb_keep_on=1 a5fb_noconsole=1 sweetfb_native=1
```

`DEVICE=dream2lte` (a) puts `samsung,dream2lte` first in the ADT, (b) builds the loader with a read-only FTS probe at 0x49 (`-DDREAM2LTE`), and (c) appends `s8fts=1` to the boot args.

## 3. Flash

Write only BOOT (`sda7`) and USERDATA. Resolve USERDATA by name: `adb shell readlink -f /dev/block/platform/*/by-name/USERDATA` (expect `/dev/block/sda27`). Check the result before every write.

## 4. Touch (draft, expect to iterate)

The S8+ touch driver (`tools/dreamlte/dreamlte_touch.c`, boot arg `s8fts=1`) starts the FTS with the command order of mainline `stmfts.c` (READ_INFO 0x80, SYSTEM_RESET 0xA0, SLEEP_OUT 0x91, SENSE_ON 0x93) and reads events with 0x86. It is **not known** whether the FTS8CD56 follows that layout, so:

- The first 48 events are logged raw as `S8 TOUCH: raw xx xx xx xx xx xx xx xx`. Touch the screen during boot, then read the log (`pull-sweetlog.ps1`).
- `s8fts_fmt=0` (default) uses the mainline `stmfts` event layout, `s8fts_fmt=1` the Samsung `fts_ts` style. If taps land in the wrong place or not at all, send me the raw lines and the matching decoder can be fixed from real bytes.
- In the loader log, `fts info` / `fts status` lines show whether the chip answers at 0x49 at all.

## 5. Back to Android

Restore BOOT from `backup/s8plus-facts/BOOT.img` (or the TWRP backup), then "Format Data" in TWRP.

## What changed for the S8+

- `tools/mkadt_dreamlte.py --device dream2lte`, `tools/dreamlte/make-boot.sh` (`DEVICE=`): platform identity and boot args.
- `shim/dreamlte/touch_probe.c`, `build.sh`: FTS read-only probe under `-DDREAM2LTE`.
- `tools/dreamlte/dreamlte_touch.c` and `xnu/patches/0124-dreamlte-s8.patch`: FTS driver behind `s8fts=1` (S8 behaviour unchanged: output identical to the old code over 46,751 simulated events).
- `tools/dreamlte/pull-sweetlog.ps1`: resolves USERDATA by name.
- `tools/dream2lte/`: fact collection and comparison.

Still unverified: that the kernel boots on the S8+, the FTS8 event layout, the power-up sequence, and everything past the lock screen.
