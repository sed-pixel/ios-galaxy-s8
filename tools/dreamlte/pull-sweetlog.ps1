param([Parameter(Mandatory)][string]$Name)
# Pull the logs of the previous iOS boot from a Galaxy S8 in TWRP:
#  - the kernel's on-disk console ring (last 1025 blocks of USERDATA; the
#    partition is resolved by name: sda24 on the S8, sda27 on the S8+),
#    decoded with tools/sweet-log.py -> logs/sweetlog-NAME.txt
#  - the loader + early kernel text in ramoops pmsg -> logs/pmsg-NAME.txt
# Usage: tools\dreamlte\pull-sweetlog.ps1 v25
$ErrorActionPreference = 'Continue'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $repo 'logs'
New-Item -ItemType Directory -Force $dir | Out-Null
$bin = Join-Path $dir "sweetlog-$Name.bin"
$txt = Join-Path $dir "sweetlog-$Name.txt"
$pmsg = Join-Path $dir "pmsg-$Name.txt"
adb shell 'p=$(readlink -f /dev/block/platform/*/by-name/USERDATA); b=$(blockdev --getsize64 $p); dd if=$p of=/tmp/slog.bin bs=4096 skip=$((b/4096-1025)) count=1025 2>/dev/null'
adb pull /tmp/slog.bin $bin | Out-Null
adb pull /sys/fs/pstore/pmsg-ramoops-0 $pmsg | Out-Null
$wslBin = (wsl -d Ubuntu wslpath -a ($bin -replace '\\', '/')).Trim()
$wslTxt = (wsl -d Ubuntu wslpath -a ($txt -replace '\\', '/')).Trim()
$wslTool = (wsl -d Ubuntu wslpath -a ((Join-Path $repo 'tools\sweet-log.py') -replace '\\', '/')).Trim()
wsl -d Ubuntu python3 $wslTool $wslBin $wslTxt
Write-Output "kernel log: $txt"
Write-Output "pmsg log:   $pmsg"
