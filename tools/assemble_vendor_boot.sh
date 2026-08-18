#!/usr/bin/env bash
# Post-processes `mka vendorbootimage`'s output into the vendor_boot.img
# that actually boots both modes on real hardware.
#
# Background (full story in README.md's KNOWN ISSUE / RESOLVED section):
# this device's bootloader loads the vendor ramdisk's PLATFORM (type 0x1,
# "generic") fragment ALONE for normal Android boot - never concatenated
# with the RECOVERY (type 0x2) fragment the way recovery-mode boot does.
# `mka vendorbootimage` builds the PLATFORM fragment from this AOSP-13
# tree's own build outputs, which can never replicate stock/MIUI's own
# proprietary vendor-ramdisk bootstrap content (init variant, linkerconfig,
# sepolicy, prop.default, res/, etc. - confirmed via byte-for-byte
# comparison against a real stock vendor_boot.img dump: stock's PLATFORM
# fragment decompresses to ~70MB of real content, this tree's own build
# only ever produced first_stage_ramdisk/fstab + kernel modules, ~35MB).
# Normal boot only ever worked again once the PLATFORM fragment was
# replaced with stock's own, unmodified, byte-for-byte - vendor_boot_stock/
# vendor_ramdisk00.stock.lz4 in this same directory is that exact blob,
# extracted once from this device's own factory-shipped vendor_boot.img
# and committed here since this tree's own build can't regenerate it.
#
# The RECOVERY fragment (TWRP itself) still comes from this tree's own
# build every time - only its embedded lib/modules/*.ko get stripped
# here, since stock's PLATFORM fragment already ships the identical
# 210 files (this tree's own modules were extracted from the very same
# firmware in the first place) and recovery mode concatenates both
# fragments, so keeping two copies just wastes space against the hard
# 64MB BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE budget.
#
# Two further stock-fragment files needed the same kind of override
# *inside this tree's own recovery ramdisk* (not handled by this script -
# already part of the normal build via recovery/root/system/etc/vintf/
# manifest/): android.hardware.health-service.example.xml and
# android.hardware.boot-service.mtk.xml both ship in stock's PLATFORM
# fragment declaring `<manifest version="9.0" type="device">` - a version
# this tree's AOSP-13 libvintf (@4.0) can't parse, at a path scanned as
# the *framework* manifest set regardless of the file's own `type`
# attribute. One bad fragment poisons every getFrameworkHalManifest()
# call for the whole directory, which is what caused keystore2's
# `Check failed: serviceManager.get() Failed to get ServiceManager`
# crash-loop (TWRP booting to a stuck splash screen) - confirmed live,
# and confirmed fixed by shipping harmless zero-HAL replacements at the
# same two paths so this tree's own recovery fragment's cpio entries win
# the directory-merge over stock's.
#
# Usage: run after `mka vendorbootimage` (needs $OUT/vendor_boot.img to
# already exist), from anywhere:
#   device/xiaomi/taiko/tools/assemble_vendor_boot.sh
#
# Requires (all already used elsewhere in this tree's build/tooling):
# python3, lz4 (legacy/chunked mode via `-l`), cpio, and this tree's own
# built out/host/linux-x86/bin/mkbootimg + system/tools/mkbootimg's
# unpack_bootimg.py.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOP="$(cd "$DEVICE_DIR/../../.." && pwd)"

OUT="${OUT:-$TOP/out/target/product/taiko}"
MKBOOTIMG="$TOP/out/host/linux-x86/bin/mkbootimg"
UNPACK_BOOTIMG="$TOP/system/tools/mkbootimg/unpack_bootimg.py"
STOCK_PLATFORM_FRAGMENT="$DEVICE_DIR/vendor_boot_stock/vendor_ramdisk00.stock.lz4"

if [ ! -f "$OUT/vendor_boot.img" ]; then
    echo "error: $OUT/vendor_boot.img not found - run 'mka vendorbootimage' first" >&2
    exit 1
fi
if [ ! -x "$MKBOOTIMG" ]; then
    echo "error: $MKBOOTIMG not built - run 'mka mkbootimg' first" >&2
    exit 1
fi
if [ ! -f "$STOCK_PLATFORM_FRAGMENT" ]; then
    echo "error: $STOCK_PLATFORM_FRAGMENT missing" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== unpacking this build's own vendor_boot.img =="
python3 "$UNPACK_BOOTIMG" --boot_img "$OUT/vendor_boot.img" --out "$WORK/unpacked" --format mkbootimg > "$WORK/mkbootimg_args.txt"

# Pull just the header/geometry args mkbootimg.py already computed for us
# (pagesize/offsets/cmdline/etc. all come from this tree's own BoardConfig.mk
# so they stay correct even though the PLATFORM fragment gets swapped out).
ARGS="$(cat "$WORK/mkbootimg_args.txt")"

echo "== stripping duplicate lib/modules/*.ko from this build's RECOVERY fragment =="
lz4 -d -f "$WORK/unpacked/vendor_ramdisk01" "$WORK/recovery.decompressed"

python3 - "$WORK/recovery.decompressed" "$WORK/recovery.trimmed.cpio" <<'PYEOF'
import sys

def filter_cpio(infile, outfile, skip_prefix):
    with open(infile, 'rb') as f:
        data = f.read()
    out = bytearray()
    pos = 0
    n = len(data)
    kept = skipped = 0
    while pos < n:
        if data[pos:pos + 6] != b'070701':
            raise ValueError(f"bad cpio magic at offset {pos}: {data[pos:pos + 6]!r}")
        header = data[pos:pos + 110]
        namesize = int(header[94:102], 16)
        filesize = int(header[54:62], 16)
        name_start = pos + 110
        name = data[name_start:name_start + namesize - 1]
        name_end = name_start + namesize
        pad1 = (4 - (name_end % 4)) % 4
        data_start = name_end + pad1
        data_end = data_start + filesize
        pad2 = (4 - (data_end % 4)) % 4
        entry_end = data_end + pad2
        namestr = name.decode('utf-8', errors='replace')
        if namestr == 'TRAILER!!!':
            out += data[pos:entry_end]
            pos = entry_end
            break
        if namestr.startswith(skip_prefix):
            skipped += 1
            pos = entry_end
            continue
        out += data[pos:entry_end]
        kept += 1
        pos = entry_end
    print(f"cpio filter: kept={kept} skipped={skipped} out_size={len(out)}", file=sys.stderr)
    with open(outfile, 'wb') as f:
        f.write(out)

filter_cpio(sys.argv[1], sys.argv[2], 'lib/modules/')
PYEOF

lz4 -l -12 -f "$WORK/recovery.trimmed.cpio" "$WORK/recovery.trimmed.lz4" > /dev/null

echo "== reassembling final vendor_boot.img (stock PLATFORM + this tree's own RECOVERY) =="
# Replace mkbootimg.py's own --vendor_ramdisk_fragment for type 1 (the
# PLATFORM one, whichever path it printed) with the committed stock blob,
# and swap type 2's (RECOVERY) fragment path for our freshly-trimmed one.
FINAL_ARGS="$(python3 - "$ARGS" "$STOCK_PLATFORM_FRAGMENT" "$WORK/recovery.trimmed.lz4" <<'PYEOF'
import shlex
import sys

args = shlex.split(sys.argv[1])
stock_platform = sys.argv[2]
trimmed_recovery = sys.argv[3]

out = []
i = 0
frag_type = None
while i < len(args):
    tok = args[i]
    if tok == '--ramdisk_type':
        frag_type = args[i + 1]
        out += [tok, args[i + 1]]
        i += 2
        continue
    if tok == '--vendor_ramdisk_fragment':
        if frag_type == '1':
            out += [tok, stock_platform]
        elif frag_type == '2':
            out += [tok, trimmed_recovery]
        else:
            out += [tok, args[i + 1]]
        i += 2
        continue
    out.append(tok)
    i += 1

print(' '.join(shlex.quote(a) for a in out))
PYEOF
)"

# shellcheck disable=SC2086
eval "$MKBOOTIMG" $FINAL_ARGS --vendor_boot "$WORK/vendor_boot.final.img"

SIZE=$(stat -c%s "$WORK/vendor_boot.final.img")
BUDGET=67108864
echo "== final vendor_boot.img: $SIZE bytes (budget $BUDGET) =="
if [ "$SIZE" -gt "$BUDGET" ]; then
    echo "error: exceeds BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE ($BUDGET) - RECOVERY fragment grew too large, trim more before flashing" >&2
    exit 1
fi

cp "$WORK/vendor_boot.final.img" "$OUT/vendor_boot.img"
echo "== wrote $OUT/vendor_boot.img =="
