#!/bin/bash
# Prepare Ubuntu on WSL2 for building the iOS root image of this port.
#   bash tools/dream2lte/wsl-setup.sh
# Installs the tools tools/mkiosroot.sh and tools/dreamlte/make-boot.sh need,
# including apfs-fuse (from apt if the package exists, else built from source).
# Asks for your Ubuntu password (sudo). Safe to run twice. It does NOT touch
# your phone and does not download Apple software.
set -euo pipefail

say() { printf '\n== %s\n' "$*"; }

say "Free space on the Windows C: drive (WSL stores its disk there)"
avail=$(df -BG --output=avail /mnt/c | tail -1 | tr -dc '0-9')
echo "C: has ${avail} GB free"
if [ "${avail:-0}" -lt 30 ]; then
    echo "Stop: the iOS image work needs about 30 GB free on C:, you have ${avail:-0} GB." >&2
    echo "Free up space on C: first, then run this again." >&2
    exit 1
fi

say "Installing packages (needs your Ubuntu password)"
sudo apt-get update
sudo apt-get install -y \
    hfsprogs rsync python3 curl unzip git fuse3 kmod build-essential \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu

say "apfs-fuse (reads the APFS disk images inside Apple's firmware)"
if command -v apfs-fuse >/dev/null 2>&1; then
    echo "already installed: $(command -v apfs-fuse)"
elif apt-cache show apfs-fuse >/dev/null 2>&1 && sudo apt-get install -y apfs-fuse; then
    echo "installed from apt"
else
    echo "no apt package: building from source (a few minutes)"
    sudo apt-get install -y cmake g++ libfuse3-dev libbz2-dev zlib1g-dev libicu-dev libattr1-dev pkg-config
    src=$(mktemp -d)
    git clone --depth 1 --recursive https://github.com/sgan81/apfs-fuse.git "$src/apfs-fuse"
    mkdir "$src/apfs-fuse/build"
    (cd "$src/apfs-fuse/build" && cmake .. && make -j"$(nproc)")
    sudo install -m 0755 "$src/apfs-fuse/build/apfs-fuse" /usr/local/bin/apfs-fuse
    rm -rf "$src"
fi

say "Checking everything the image build needs"
ok=1
for t in apfs-fuse mkfs.hfsplus fsck.hfsplus rsync python3 aarch64-linux-gnu-gcc aarch64-linux-gnu-objcopy mount; do
    if command -v "$t" >/dev/null 2>&1; then printf '  ok       %s\n' "$t"; else printf '  MISSING  %s\n' "$t"; ok=0; fi
done
if grep -q '[[:space:]]hfsplus$' /proc/filesystems; then
    echo "  ok       hfsplus file-system driver is loaded"
else
    echo "  TODO     hfsplus driver not loaded yet: install hfsplus.ko from the GitHub build (next step)"
fi
[ -e /dev/fuse ] && echo "  ok       /dev/fuse" || { echo "  MISSING  /dev/fuse"; ok=0; }
[ "$ok" = 1 ] && say "Setup finished: all tools present" || { say "Some tools are missing (see above)"; exit 1; }
