#!/usr/bin/env python3
"""Compare a Galaxy S8+ fact dump against the S8 values this port hardcodes.

    compare_facts.py backup/s8plus-facts

Reads the files written by collect-facts.sh and prints one line per fact:
  MATCH    the S8+ has the same value the S8 code assumes
  NOTE     differs from the S8 but is already handled (read the line)
  DIFF     the S8+ differs: change the code/docs before flashing anything
  UNKNOWN  the dump does not show it: check by hand
Exit status 1 if any DIFF or UNKNOWN is left. A clean run still proves nothing
about iOS booting; it only removes known reasons for the S8 build to fail.
"""
import re
import sys
from pathlib import Path

# Constants copied from the S8 sources (file noted for each).
S8 = {
    'fb_base': 0xcc000000,        # shim/dreamlte/loader.c FB_BASE, mkadt_dreamlte.py FB_PHYS
    'fb_size': (1440, 2960),      # same files, FB_W/FB_H
    'ram_bank': (0x880000000, 0x8ffffffff),   # loader.c XNU_RAM_BASE, mkadt DRAM_BASE
    'ramoops_base': 0x92000000,   # loader.c RAMOOPS_CONSOLE (zone 0x92080000)
    'boot': 'sda7',               # docs/s8-install.md
    'userdata': 'sda24',          # tools/dreamlte/pull-sweetlog.ps1
    'touch': 'sec_ts',            # shim/dreamlte/touch_probe.c, S6SY761 at 0x48
}


def read(d, name):
    p = d / name
    return p.read_text(errors='replace') if p.exists() else ''


def main(d):
    d = Path(d)
    rows = []

    def add(state, what, detail):
        rows.append((state, what, detail))

    dev = read(d, 'product_device.txt').strip()
    add('MATCH' if dev == 'dream2lte' else 'DIFF', 'device codename',
        f'{dev or "?"} (expected dream2lte)')

    cmd = read(d, 'cmdline.txt')
    m = re.search(r's3cfb\.bootloaderfb=(0x[0-9a-fA-F]+)', cmd)
    if m:
        v = int(m.group(1), 16)
        add('MATCH' if v == S8['fb_base'] else 'DIFF', 'S-Boot framebuffer',
            f'{v:#x} (S8 code uses {S8["fb_base"]:#x}); loader.c, display_probe.c, '
            f'mkadt_dreamlte.py and apply-dreamlte.py all hardcode it')
    else:
        add('UNKNOWN', 'S-Boot framebuffer', 's3cfb.bootloaderfb not in /proc/cmdline')

    size = re.search(r'(\d{3,4})\D+(\d{3,4})', read(d, 'fb0-size.txt'))
    if size:
        wh = (int(size.group(1)), int(size.group(2)))
        # fb0 virtual_size is often N screens stacked (double/triple buffering):
        # 1440x5920 on the S8+ is two 1440x2960 buffers.
        w, h = S8['fb_size']
        ok = wh[0] == w and wh[1] % h == 0 and wh[1] // h >= 1
        add('MATCH' if ok else 'DIFF', 'panel mode',
            f'{wh[0]}x{wh[1]} = {wh[1] // h if ok else "?"} buffer(s) of {w}x{h} '
            f'(S8 code uses {w}x{h}; TWRP fb0 virtual size)')
    else:
        add('UNKNOWN', 'panel mode', 'fb0 size not in the dump; confirm 1440x2960 by hand')

    iomem = read(d, 'iomem.txt')
    lo, hi = S8['ram_bank']
    ram = [(int(a, 16), int(b, 16)) for a, b in
           re.findall(r'^\s*([0-9a-f]+)-([0-9a-f]+) : System RAM', iomem, re.M)]
    ok = any(a <= lo and hi <= b for a, b in ram)
    add('MATCH' if ok else 'DIFF', 'XNU RAM bank',
        f'{lo:#x}-{hi:#x} {"inside" if ok else "NOT inside"} System RAM '
        f'({", ".join(f"{a:x}-{b:x}" for a, b in ram)})')
    carve = [l.strip() for l in iomem.splitlines()
             if re.match(r'\s*8[89][0-9a-f]{7}-', l) and 'System RAM' not in l]
    add('MATCH' if not carve else 'DIFF', 'carve-outs in that bank',
        'none' if not carve else '; '.join(carve[:4]))

    ramoops = read(d, 'ramoops.txt') + iomem
    add('MATCH' if f'{S8["ramoops_base"]:x}' in ramoops else 'UNKNOWN', 'TWRP ramoops base',
        f'{S8["ramoops_base"]:#x} ' + ('found' if f'{S8["ramoops_base"]:x}' in ramoops
                                       else 'not found; boot logs may not land in pstore'))

    names = {}
    for line in read(d, 'by-name.txt').splitlines():
        mm = re.search(r'\s(\S+) -> \S*/(sd[a-z]\d+)$', line.strip())
        if mm:
            names[mm.group(1)] = mm.group(2)
    got = names.get('BOOT')
    add('MATCH' if got == S8['boot'] else ('DIFF' if got else 'UNKNOWN'),
        'BOOT partition', f'{got or "not listed"} (S8 docs/scripts use {S8["boot"]})')
    # USERDATA differs by device (S8 sda24, S8+ sda27). The loader, kernel,
    # flash-chunks.ps1 and pull-sweetlog.ps1 resolve it by name, so any number
    # is fine as long as it is listed; the install docs must not hardcode it.
    got = names.get('USERDATA')
    add('MATCH' if got else 'UNKNOWN', 'USERDATA partition',
        f'{got or "not listed"} (found by name; S8 was {S8["userdata"]}, '
        f'never type the S8 number)')
    if names.get('CP_DEBUG') == S8['userdata']:
        add('NOTE', 'sda24 on this phone', 'is CP_DEBUG, NOT the data partition')

    i2c = read(d, 'i2c-devices.txt')
    sec = [l for l in i2c.splitlines() if S8['touch'] in l or 's6sy761' in l.lower()]
    fts = [l for l in i2c.splitlines() if 'fts_touch' in l.lower() or 'stm,fts' in l.lower()]
    if sec:
        add('MATCH', 'touch controller', f'{sec[0].strip()} (S6SY761 path, as on the S8)')
    elif fts:
        add('NOTE', 'touch controller',
            f'{fts[0].strip()}: STM FTS, not the S8 chip. Needs the s8fts=1 draft '
            f'driver (DEVICE=dream2lte make-boot.sh adds it); UNTESTED')
    else:
        add('DIFF', 'touch controller', 'neither sec_ts nor fts_touch found on i2c')

    dtb = (d / 'live.dtb')
    blob = dtb.read_bytes() if dtb.exists() else b''
    for needle, why in ((b'samsung,exynos8895', ''),
                        (b'interrupt-controller@10200000', 'GIC base; S8 code uses GICD 0x10201000')):
        add('MATCH' if needle in blob else 'UNKNOWN', f'live DT has {needle.decode()}', why)
    add('MATCH' if (b'sec,sec_ts' in blob or b'stm,fts_touch' in blob) else 'UNKNOWN',
        'live DT touch node', 'sec,sec_ts (S8) or stm,fts_touch (S8+)')

    width = max(len(r[1]) for r in rows)
    for state, what, detail in rows:
        print(f'{state:8} {what:{width}}  {detail}')
    bad = [r for r in rows if r[0] in ('DIFF', 'UNKNOWN')]
    notes = [r for r in rows if r[0] == 'NOTE']
    print(f'\n{len(rows) - len(bad) - len(notes)} match, {len(notes)} notes, '
          f'{len(bad)} need attention')
    return 1 if bad else 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
