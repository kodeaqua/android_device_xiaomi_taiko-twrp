# TWRP Tree for Redmi Pad 2 (taiko)

Xiaomi Redmi Pad 2, MediaTek Helio G100 (mt6789 platform family).

This tree was bootstrapped from the `device/xiaomi/rock` (POCO M5, Helio G99)
TWRP tree, since both boards share the same mt6789 SoC family and boot image
layout. All board/partition/kernel-module data below was re-derived from a
real taiko retail fastboot ROM (`taiko_global_images_OS3.0.304.0.WOVMIXM`),
not just renamed from rock.

STABLE TREE:

FLASHING ROM (partition/fstab layout verified against retail images) √
FLASHING GSI √
TOUCH — verified working on real hardware (nt36xxx_spi + real firmware, see below) √
ROTATION — verified working on real hardware (TW_ROTATION := 180, see below) √
DECRYPTION — real mitee KeyMint/Gatekeeper HAL, verified working end-to-end on real
  hardware, including /data that a real Android system (GSI) encrypted - see the
  DECRYPTION section for why that needed PLATFORM_VERSION := 99 √
NORMAL BOOT ("boot to System") — verified working on real hardware, same as
  TWRP/recovery mode, from the image `mka vendorbootimage` produces directly √

## What was re-derived from the real taiko firmware

- `boot.img` / `vendor_boot.img` unpacked with `system/tools/mkbootimg`:
  kernel, vendor ramdisk fragments (generic + "recovery"), and DTB pulled
  directly from the retail images.
- Kernel base/offsets (kernel/ramdisk/tags/dtb) cross-checked against the
  real vendor_boot header — they match rock's values exactly (same mt6789
  boot image layout), so they were left untouched.
- `BOARD_DTB_SIZE`, `prebuilt/kernel`, `prebuilt/dtb` — replaced with the
  real taiko kernel/DTB blobs.
- `fstab.emmc`, `fstab.mt6789`, `recovery/root/system/etc/recovery.fstab` —
  replaced verbatim with the real taiko fstabs extracted from the vendor
  ramdisk (these list `system_ext`, `mi_ext`, `vendor_dlkm`, `odm_dlkm`,
  `system_dlkm` and both `erofs`/`ext4` candidates per partition, none of
  which were present in the old rock-derived fstabs).
- `recovery/root/lib/modules/*` — replaced with taiko's real 210 kernel
  modules (pulled from the vendor ramdisk's generic fragment), including
  its actual tablet display panels (o84/tianma/jdi/samsung DSC panels) and
  charging ICs (sy6976/nu6601/sc6601), instead of rock's phone panel and
  charger modules.
- `BOARD_SUPER_PARTITION_SIZE`, `BOARD_MAIN_DYNAMIC_PARTITIONS_SIZE`,
  `BOARD_MAIN_DYNAMIC_PARTITIONS_PARTITION_LIST` — derived from parsing the
  real `super.img` liblp metadata (desparsed + parsed by hand): total super
  size `0x2c0000000`, dynamic partitions `system vendor product system_ext
  odm_dlkm vendor_dlkm system_dlkm mi_ext`.
- `BOARD_*_FILE_SYSTEM_TYPE` set to `erofs` — confirmed by reading the
  `vendor_a` partition's superblock magic straight out of `super.img`.

## Panel / digitiser variants

taiko ships with three interchangeable panel + touch-controller
combinations. The panel drivers for all three are already in the factory
vendor_boot ramdisk fragment (`modules.load.recovery` lines 82-84), but the
digitiser drivers are not — they live on `/vendor_dlkm`, and stock
`modules.load` (lines 105-109) loads **all** of them on **every** unit:

| Panel module | Digitiser driver | TP IC | Firmware |
|---|---|---|---|
| `panel-o84-35-02-0b-dsc-vdo` | `nt36xxx_spi.ko` | Novatek NT36523N (BOE) | `novatek_ts_fw_boe.bin` |
| `panel-o84-36-02-0a-dsc-vdo` | `nt36xxx_spi.ko` | Novatek NT36536 (Tianma) | `novatek_ts_fw_tm.bin` |
| `panel-o84-42-03-0c-dsc-vdo` | `focaltech_tp.ko` | FocalTech FT8205P (Huaxing) | `focaltech_ts_fw_huaxing.bin` |

Each driver reads the active panel on probe and bails out
(`TP_COMPATIBLE IS NOT CORRECT!` / `Not found compatible node`) when it is
not the one bound to this unit, so loading both drivers is safe on any
variant — it is exactly what stock does.

Both drivers, `xiaomi.ko` and `xiaomi_headset_touch_notifier.ko` (the two
shared dependencies not already in the factory fragment) and all three
firmware blobs are committed under `recovery/root/`. Getting any of this
wrong is not a degradation, it is total loss of touch: the driver probes
normally, defers its firmware upload, then fails the `firmware_request` with
nothing to fall back on, because TWRP has long since unmounted the real
`/vendor`.

The MP blobs (`novatek_ts_mp_*.bin`, `focaltech_mp_fw_huaxing.ini`, ~450KB)
are only read by the factory self-test proc entries and can be dropped if
vendor_boot ever runs short of space.

## Caveats / follow-up work

- **TEE / decryption**: rock's tree bundled a Trustonic "beanpod" TEE stack
  (`teei_daemon`, `keymint-beanpod`, `/vendor/thh/ta/*`) into the recovery
  ramdisk for FBE password decryption. taiko's real kernel module list loads
  `mitee.ko` instead — Xiaomi's own in-house TEE, not Trustonic — so that
  bundle would never have worked (different wire protocol, different `.ta`
  format) and was correctly dropped rather than shipped unverified.
  Getting real FBE decryption needed taiko's own mitee-based KeyMint/
  Gatekeeper HAL, which was unavailable earlier for lack of erofs-utils/root
  to unpack the EROFS `vendor` partition — since resolved. The real stack
  was extracted from the retail vendor.img (`super.img` → unsparse →
  `lpunpack -p vendor_a` → EROFS extract) and bundled verbatim:

  > Note on tooling: none of `simg2img`, `lpunpack` or `fsck.erofs` is
  > prebuilt anywhere in this checkout, and `out/` is empty on a fresh
  > clone, so "already present in this tree" means *source* is present, not
  > that a binary is. `external/erofs-utils` here is 1.2.1, which ships
  > `mkfs` and `fuse` but no `fsck` — so there is no `--extract` to build.
  > Its `lib/` does contain the whole read path (`super.c`, `namei.c`,
  > `data.c`, `zmap.c`, `decompress.c`), which is enough to link a ~200-line
  > extractor against, with `external/lz4` for the decompressor. `super.img`
  > out of a Xiaomi fastboot package is an Android **sparse** image, so it
  > needs unsparsing before any of the liblp offsets make sense.

  - `vendor/bin/hw/android.hardware.security.keymint@4.0-service.mitee`
  - `vendor/bin/hw/android.hardware.gatekeeper-service.mitee`
  - `vendor/bin/tee-supplicant` (talks to `/dev/tee0`, created by `mitee.ko`)
  - `vendor/lib64/*.so` — real dependency closure per `readelf -d` on the
    two service binaries (libc/liblog/libbinder_ndk/etc. were already
    present as standard TWRP/AOSP recovery dependencies, not re-bundled)
  - `vendor/mitee/ta/*.ta` — 13 trusted-application blobs (~7.3MB), bundled
    unfiltered since individual TA purposes aren't documented and mitee TAs
    may depend on each other
  - `vendor/etc/init/*.rc` — verbatim stock rc files (the tee-supplicant
    one's `on fs` block does the `/dev/tee0` chmod/chown, `enable`s the
    keymint service, and starts tee-supplicant)
  - `vendor/etc/vintf/manifest.xml` + per-service `manifest/*.xml`
    fragments — were completely absent before, which is a real bug
    (separate from TWRP's own cosmetic `Process_Keymaster_Version()`
    logging in `bootable/recovery/partitionmanager.cpp`, confirmed to only
    ever look for the legacy HIDL `android.hardware.keymaster` name — it
    will keep logging an empty `keymaster_ver` on this modern all-AIDL
    device regardless, but that value isn't read anywhere else in
    bootable/recovery, so it's harmless/cosmetic only)
  - `vendor/etc/selinux/vendor_tee_service_contexts`

  `TW_INCLUDE_CRYPTO` is re-enabled accordingly.

  **Verified working on real hardware**, after a long chain of fixes (each
  only discoverable by testing the previous one on-device — see git log for
  the full sequence, commits `e454ed7`..`0fffcc4` and later). Root causes
  found, in order:
  1. **Library filename collisions**: 5 of the bundled real-firmware libs
     (`lib_android_keymaster_keymint_utils.so`, `libcppbor_external.so`,
     `libgatekeeper.so`, `libkeymaster_portable.so`, `libkeymint.so`) share
     their exact filename with modules this AOSP-13 tree's own
     `system/keymaster` builds and installs to `/system/lib64` — different,
     incompatible content. Renamed all 5 with a `_mitee` suffix and
     `patchelf --replace-needed` on every consumer. **Also had to
     `patchelf --set-soname`** on all 5 renamed files — renaming just the
     filename isn't enough; the internal DT_SONAME field still said the old
     name, so bionic's soinfo registry kept resolving the *old* soname to
     whichever copy loaded first, silently shadowing the real
     `/system/lib64` one for any consumer that needed the old (non-KmVersion)
     symbol overloads. `nm -D`/nm-based cross-referencing plus manually
     running the binary (`adb shell /vendor/bin/hw/...`) and reading the
     exact `CANNOT LINK EXECUTABLE` error was the only way to find these.
  2. **ABI/toolchain gap**: taiko's real firmware binaries were built
     against a newer NDK/BoringSSL than this tree ships. Chased down one
     missing symbol at a time (each found by running the binary manually
     and reading the next linker error): `std::__libcpp_verbose_abort`,
     `AIBinder_Class_setTransactionCodeToFunctionNameMap`, the
     `OPENSSL_sk_*` BoringSSL rename family, `ASN1_TIME_set_posix`. All
     implemented as a single small local Soong module,
     `device/xiaomi/taiko/libcxx_compat_shim/` (`libcxx_verbose_abort_shim_
     mitee.so`), `patchelf --add-needed` onto every affected binary.
  3. **Missing SELinux `seclabel`**: none of the 3 services in
     `tee-supplicant.rc` had one, and there's no file_contexts entry for any
     of the 3 backing binaries. Without a resolvable context, init silently
     drops the service — `getprop init.svc.X` came back completely empty
     (not even `stopped`), which is the tell. Fixed by adding `seclabel
     u:r:recovery:s0` (matching every other service in this tree) to all 3.
  4. **`/mnt/vendor/persist` never mounted**: it's declared in
     `recovery.fstab` but that only registers it with TWRP's own GUI mount
     manager, not an automatic boot-time mount. mitee's TA needs real
     storage there (RPMB-backed key material) - without it, keymint-mitee
     SIGABRTs immediately (`MiteeKeymint_ipc: Check failed: status ==
     STATUS_OK`, TEEC `oresult=TEEC_ORIGIN_TRUSTED_APP`, from a TEE call
     that touches persistent storage). Fixed with a `sleep 8`-then-mount
     `oneshot` service (`mount_persist_delayed` in `tee-supplicant.rc`) —
     every trigger tried (`on fs`, `on post-fs`,
     `on property:hwservicemanager.ready=true`) fired too early on this
     device, racing against (and losing to) TWRP's own partition-manager,
     which briefly mounts+unmounts persist during its early startup scan
     (`recovery.fstab`'s persist line has the `check` flag) — confirmed via
     logcat: the kernel logged a real `EXT4-fs (sdc16): mounted...` /
     `...unmounting...` pair attributed to TWRP's own process, not init.
  5. **Missing VINTF manifest entries**: the bundled
     `android.hardware.security.keymint-service.mitee.xml` fragment only
     declared the `android.hardware.security.keymint` package
     (`IKeyMintDevice`, `IRemotelyProvisionedComponent`) — the separate
     `android.hardware.security.secureclock` (`ISecureClock`) and
     `android.hardware.security.sharedsecret` (`ISharedSecret`) packages
     were missing entirely, even though the service binary registers both
     (confirmed via its `DT_NEEDED` on `...secureclock-V1-ndk.so` /
     `...sharedsecret-V1-ndk.so`). `servicemanager` rejects `addService()`
     for any AIDL interface the caller's own VINTF manifest doesn't
     declare, independent of SELinux — this was the actual cause of the
     `CHECK(status == STATUS_OK)` SIGABRT that looked like a TEE failure at
     first (disassembling the check with `llvm-objdump` — host `objdump`
     has no aarch64 support — showed it's really checking
     `AServiceManager_addService()`'s return, not any TEE call; the TEE
     side was already succeeding cleanly per `/proc/mitee_log`, the mitee
     kernel driver's own debug log, which is invaluable for this kind of
     debugging: `cat /proc/mitee_log` any time keymint-mitee misbehaves).
     Found by diffing against Evolution-X's `device_xiaomi_duchamp` (a
     sibling mt6789 Xiaomi device using the same mitee stack). Added both
     missing `<hal>` entries.

  Once all 5 were fixed, `keystore2` connects to the real KeyMint TEE
  cleanly (`Successfully registered Keystore 2.0 service`), and a
  **freshly-formatted `/data`** (via TWRP's own Wipe > Format Data) mounts
  and decrypts correctly end-to-end (real F2FS + inlinecrypt, confirmed via
  `/proc/mounts`).

  **`/data` encrypted by a real Android system also works — but only after
  fixing OS_VERSION.** For a long time it did not: reading such a key always
  failed the same way, KeyMint returning `KEY_REQUIRES_UPGRADE` (-62) and
  then `INVALID_ARGUMENT` (-38) from the `upgradeKey()` that is supposed to
  resolve it. That was misread as KeyMint's anti-rollback protection being
  an intentional, unfixable boundary. It is not. Three things were ruled out
  by direct experiment first: calling `earlyBootEnded()` before decrypting
  (it succeeded, and the -62/-38 pair stayed byte-identical), running the
  mitee services as root instead of system (helped them get further but did
  not change this), and rewriting boot.img's header patch level. The
  decisive experiment was building TWRP with a *low* patch level, formatting
  /data under it, then reading that key back with the normal build:
  `upgradeKey()` worked perfectly. So the TA's upgrade path was never
  broken - only its input was.

  `IKeyMintDevice.aidl` states the rule: `upgradeKey()` MUST return
  `INVALID_ARGUMENT` if *any* version or patch level recorded in the key is
  higher than the device's current value. `strings` on
  `vendor/lib64/libkeymint_mitee.so` shows which properties the HAL reads
  for those: `ro.build.version.release` (→ OS_VERSION),
  `ro.build.version.security_patch`, `ro.vendor.build.security_patch`. The
  patch dates were already pinned to 2099, but `PLATFORM_VERSION` was 13,
  so OS_VERSION was 130000 - while the GSI writing the key runs Android 16,
  i.e. 160000. Key above device, every single time. It also explains why a
  TWRP-created key always re-read fine: 13 against 13. `PLATFORM_VERSION`
  (and `PLATFORM_VERSION_LAST_STABLE`) are now 99, clearing any real
  release; BoardConfig.mk documents the arithmetic. BOOT_PATCHLEVEL is the
  one field not settable from here, but the bootloader hands it to the TA
  directly, identical whether this device booted TWRP or Android, so it can
  never be the mismatching one.

  Note the direction only has to hold *for reading*: keystore2 does not
  persist the upgraded blob for `Domain::BLOB` keys like vold's, so the key
  on disk keeps its original values and the real system still boots.
- **Touch**: resolved. taiko uses `nt36xxx_spi.ko` + `xiaomi.ko` (Novatek),
  loaded at runtime via `TW_LOAD_VENDOR_MODULES`. The touch IC also needs its
  firmware blob (`novatek_ts_fw_boe.bin`, pulled from a live device) uploaded
  via `request_firmware()` ~14s after module load; since
  `KernelModuleLoader::Load_Vendor_Modules()` unmounts `/vendor` right after
  loading modules (before that deferred firmware request fires), the blob is
  bundled directly into the ramdisk at `/vendor/firmware/` instead of relying
  on the real `/vendor` partition. Confirmed working on real hardware
  (~15-20s warm-up after boot before touch responds — this is expected, not
  a bug).
- **Rotation**: resolved. taiko's panel scans out 180° rotated from the
  theme's native layout (confirmed on real hardware: without this, TWRP's
  "Install" button visually renders bottom-right instead of top-left, and
  tapping it opens the wrong page). Fixed with `TW_ROTATION := 180`.
- **Brightness/thermal paths**: `TW_BRIGHTNESS_PATH`, `TW_MAX_BRIGHTNESS`,
  `TW_CUSTOM_CPU_TEMP_PATH` are carried over from rock unverified; confirm
  against real sysfs on-device.
- **Theme**: `TW_THEME := portrait_hdpi` kept as-is; works correctly with
  `TW_ROTATION := 180` on taiko's 11" 2000x1200 panel.
- **Build quirk — stale `libminuitwrp.so` in incremental builds**: when
  iterating on `bootable/recovery/minuitwrp/*.cpp` (e.g. for local rotation
  debugging), `mka vendorbootimage` can silently repack the ramdisk with a
  *stale* `libminuitwrp.so` even though the source recompiled correctly —
  the `Install:` step that copies the freshly-linked `.so` into
  `$OUT/recovery/root/system/lib64/` isn't reliably re-triggered by ninja on
  incremental builds. If a source change to that file doesn't seem to take
  effect on-device, verify by unpacking the built `vendor_boot.img`
  (`unpack_bootimg.py`, decompress the "recovery" vendor ramdisk fragment
  with `lz4`, extract with `cpio`) and checking
  `system/lib64/libminuitwrp.so` directly against
  `$OUT/target/product/taiko/system/lib64/libminuitwrp.so` (md5sum) rather
  than trusting ninja's "no work to do". A clean forced rebuild (delete
  `vendor_boot.img`, `ramdisk_files-timestamp`, `recovery.cpio.lz4`, and the
  stale `.so` copies, then rebuild) resolves it.

## vendor_boot.img: normal boot + TWRP splash-hang, both resolved

**Status: fixed and verified live on real hardware - both normal Android
boot and TWRP's own recovery GUI work from the same `vendor_boot.img`.**
This took the rest of the night after the section below was first written;
kept mostly intact underneath as the record of how the actual fix was
found, since the mechanism it establishes (normal boot loads the vendor
ramdisk's `type 0x1` fragment *alone*, recovery mode concatenates
`type 0x1` + `type 0x2`) is still exactly right and is what the fix relies
on - only the "unsolved" conclusion at the end was wrong.

**Confirmed regression point** (found by bisecting saved builds in
`C:\Users\Aqua\Documents`): `twrp-taiko-eng-20260817-2149-4c80fbe.img` boots
to System; every build after it (starting with `03e09bf`) doesn't, including
every crypto-era build tonight. Comparing their vendor ramdisk tables:

- `4c80fbe` (works): **one** fragment, tagged `type 0x1`, 41.9MB - built with
  only `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true`.
- `03e09bf` onward (broken): **two** fragments - `type 0x1` "generic" (this
  tree's own minimal AOSP ramdisk, 2.7MB, unchanged size across every commit
  since) + `type 0x2` "recovery" (TWRP's root, grows every commit) - built
  after also adding `BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true`.
  BoardConfig.mk's own comment explains *why* that flag got added: the
  single-fragment build crashes the bootloader (MTK AEE `LK_CRASH`,
  `/data/vendor/aee_exp/db.fatal.*.KE`) specifically when entering recovery
  mode, since it expects a typed "recovery" fragment to exist. So neither
  config alone is correct for this device - single-fragment breaks recovery
  entry, dual-typed-fragment (as currently built) breaks normal boot.

**Confirmed mechanism** (matches the official AOSP vendor_boot v4 spec, once
you actually test it against this device rather than assume): the kernel
panic on every failing build (`adb shell cat /sys/fs/pstore/console-ramoops*`
after a failed System boot attempt, from Recovery) is always

```
RAMDISK: lz4 image found at block 0
<sometimes> chunk length is longer than allocated
F2FS-fs (ram0): Magic Mismatch, valid(0xf2f52010) - read(...)
... (ext3/ext2/ext4/vfat/msdos/exfat/fuseblk/f2fs/erofs all fail)
Kernel panic - not syncing: VFS: Unable to mount root fs on "/dev/ram" ...
```

i.e. the kernel treats the vendor ramdisk as a legacy `/dev/ram`-mountable
image (not cpio/initramfs) and, for **normal boot**, only loads/decompresses
the `type 0x1` fragment **by itself** - it does *not* concatenate it with
`type 0x2`. This tree's own generic fragment (this tree's own minimal AOSP-13
ramdisk, 2.7MB) is real, valid content on its own (confirmed: decompresses
cleanly standalone with `lz4 -d`) - it's just *insufficient* content for a
real first-stage boot on this device. Real taiko firmware's own generic
fragment is 27.6MB and contains a full first-stage init tree: real
`first_stage_ramdisk/fstab.mt6789`, and critically **210 real kernel
modules** (`lib/modules/*.ko`) including the storage driver itself
(`ufs-mediatek-mod.ko`) - needed before `/vendor_dlkm` (where this tree
normally loads modules from) can even be mounted, a chicken-and-egg problem
this tree's own minimal generic ramdisk was never built to solve. Recovery
mode, separately, **does** concatenate `type 0x1` + `type 0x2` (confirmed:
recovery works fine with the two-independently-compressed-fragments layout
this tree currently uses, and also worked with a from-scratch single
combined LZ4 stream split at an arbitrary point into two table entries -
both of those only reconstruct validly when concatenated, so recovery mode's
loader must be doing that concatenation itself).

**Fix direction that's confirmed necessary but not yet achieved**: `type 0x1`
needs to be a complete, standalone-valid, real first-stage ramdisk (i.e.
needs real taiko generic content, not this tree's own AOSP one) while
`type 0x2` stays this tree's TWRP recovery root, unchanged. The hard part is
budget: `BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE` / the real on-device
`vendor_boot_a` partition are both a **hard, fixed 64MB**
(`fastboot getvar partition-size:vendor_boot_a` → `0x4000000`, confirmed on
real hardware) - stock's real generic content (27.6MB compressed) plus this
tree's current recovery content (~42-44MB compressed, grows with every
crypto-era commit) together exceed that by several MB, so real content
*can't* just be swapped in unmodified; something has to shrink.

**Five approaches tried tonight, all failed** (each flashed and tested live,
then reverted back to `bf9fe3f` - the last verified-safe crypto build - before
trying the next one; `vendor_boot-STOCK-ORIGINAL.img` in the same Documents
folder is the real stock vendor_boot, kept as an always-available fallback if
System boot is ever needed urgently):
1. Merge stock's *entire* combined content (95.9MB raw, both its own
   fragments concatenated) with this tree's recovery root into one cpio via
   `mkbootfs`, compress once, split arbitrarily for the table. Compressed to
   71.5MB - straight over budget, never flashed.
2. Same idea but using this tree's own small generic ramdisk instead of
   stock's (skip stock entirely) - 45.4MB, fit budget. Recovery mode booted
   fine; normal boot still failed (same panic).
3. Split at an actual LZ4 legacy-chunk boundary instead of an arbitrary byte
   offset (in case straddling a chunk mid-block mattered) - no different
   result; still failed, with a *different* failure signature (kernel read
   stale/leftover memory content instead of hitting an LZ4 parse error),
   which is what led to the "type 0x1 loaded alone, not concatenated"
   finding above.
4. Pure single fragment (no `type 0x2` at all), reusing approach 2's merged
   content - broke *both* modes (confirms the BoardConfig.mk comment's
   LK_CRASH finding is real and still applies to this tree's current
   recovery content, not just historically).
5. Real stock generic content, aggressively trimmed (dropped 158 of 210
   kernel modules, keeping only storage/clock/power/pinctrl essentials) to
   fit budget - broke *recovery* this time (TWRP's own splash needs the
   display/panel modules that got dropped - `mediatek_drm_v1.ko`,
   `panel-*.ko`). A follow-up attempt keeping display modules but only
   dropping battery/charging-specific ones, *combined* with shrinking the
   recovery fragment (`TW_EXCLUDE_NANO`/`TW_EXCLUDE_BASH`, disabling
   `TW_INCLUDE_RESETPROP`/`REPACKTOOLS`, plus manually deleting stale
   `bash`/`nano`/`magiskboot` files ninja had left in `$OUT` from earlier
   builds - the usual ninja-staleness gotcha this tree keeps running into,
   see the `libminuitwrp.so` note further down) fit budget (65.0MB) but
   broke recovery even worse (hangs before TWRP's own splash, not just a
   failed System boot) - not fully understood why; possibly one of the
   "essential" modules kept in approach 3's list was mis-categorized, or
   removing the BASH/NANO/RESETPROP files broke something else in the
   ramdisk this tree's own init.rc or TWRP's own code depends on
   indirectly. **`BoardConfig.mk` was reverted back to exactly the `bf9fe3f`
   state** (`TW_INCLUDE_RESETPROP`/`LIBRESETPROP`/`REPACKTOOLS` restored,
   `TW_EXCLUDE_NANO`/`BASH` removed) - only this README changed.

**The actual fix, once a 6th approach was tried**: stop trying to fit
*trimmed* real generic content in budget at all - use stock's real `type
0x1` fragment **completely unmodified, byte-for-byte**, and only trim
*this tree's own* `type 0x2` (recovery) fragment enough to fit both under
64MB together. `prebuilt/vendor_ramdisk.cpio.lz4` is that exact blob
(27.6MB compressed), extracted once from this device's own factory
`vendor_boot.img` and committed here since no build
config in this tree can regenerate stock's proprietary bootstrap content
(real init variant, linkerconfig, sepolicy, prop.default, res/, etc. -
confirmed via byte comparison that this tree's own best AOSP-13 build
output, even with real kernel modules correctly added via
`BOARD_VENDOR_RAMDISK_KERNEL_MODULES`, was still less than half the size
of stock's and missing all of that). The main thing trimmed from `type
0x2` is `lib/modules/*.ko`: stock's `type 0x1` already ships 210 modules
(this tree's own copies were extracted from the same firmware originally)
and recovery mode concatenates both fragments anyway, so a second copy was
pure waste against the budget.

That trim is no longer total. As of v1.0.1 `recovery/root/lib/modules`
carries exactly four `.ko` - `xiaomi.ko`, `xiaomi_headset_touch_notifier.ko`,
`nt36xxx_spi.ko`, `focaltech_tp.ko`, 1.3MB together - because none of them
is in stock's 210. Verified by extracting the prebuilt fragment: it holds
no digitiser driver of any kind and no touch firmware. Everything those
four depend on *is* in there (miev, hqsysfs, mediatek_drm_v1,
mtk_disp_notify, mtk_panel_ext, xiaomi_usb_touch_notifier and all three
panel-o84-* variants), loaded by init from `modules.load.recovery` lines
8-197, well before this tree's own insmods run. See the *Panel / digitiser
variants* section.

This is wired into the build rather than done by a helper script, so
`mka vendorbootimage` alone produces a directly flashable image:
`build/tasks/vendor_boot.mk` (picked up by core/Makefile's
`-include $(sort $(wildcard device/*/*/build/tasks/*.mk))` at the very end,
after every image rule is defined) repoints INTERNAL_VENDOR_RAMDISK_TARGET
at the prebuilt, which is what mkbootimg's `--vendor_ramdisk` then uses.
The official BOARD_VENDOR_RAMDISK_FRAGMENT.*.PREBUILT variable only covers
the *extra* fragments, never the main one, so it cannot express this. The
RECOVERY fragment is still built from source on every compile, and the
image goes through the normal assert-max-image-size and AVB
add_hash_footer steps (which the old helper script skipped).

That fix alone got normal boot working immediately, but flashing it
revealed a second, separate problem: TWRP's own recovery GUI now hung at
the splash screen forever (kernel/init boot fine, `adb` stays reachable
throughout - a completely different failure mode from the earlier
panics). Chased through three wrong turns before finding the real cause:

1. *First theory*: `/mnt/vendor/persist`'s mount timing race (the same
   one `tee-supplicant.rc`'s `mount_persist_delayed` was already built to
   dodge) had shifted later because `hwservicemanager.ready` itself now
   fires later with all of stock's extra platform content to bring up
   first, letting TWRP's own early partition scan-then-unmount win the
   race instead of losing it. Made the delayed mount retry periodically
   instead of once - **wrong**: manually mounting persist live over adb
   mid-crash-loop proved it made no difference at all to the actual
   crash.
2. *Second theory*: `tee-supplicant`/`vendor.keymint-mitee`/
   `vendor.gatekeeper_mitee` all ran `user system`, but persist's real
   factory content includes an `otrp` dir that's `drwx------ root
   system` (0700, owner-only - the matching `system` group grants
   nothing). Changed all three to `user root` - this genuinely helped
   (keymint-mitee got much further: connected to the TEE, registered the
   HAL, answered device-info queries) but a **new** crash appeared right
   after, in `getHardwareInfo()`.
3. *Actual cause*: that new crash was always `keystore2: Check failed:
   serviceManager.get() Failed to get ServiceManager`, and logcat showed
   why - stock's `type 0x1` fragment ships exactly two files under
   `/system/etc/vintf/manifest/` (`android.hardware.health-
   service.example.xml`, `android.hardware.boot-service.mtk.xml`), both
   declaring `<manifest version="9.0" type="device">`. This tree's
   AOSP-13 `libvintf` (`@4.0`) can't parse manifest version 9.0, *and*
   `/system/etc/vintf/manifest/` is scanned as the **framework** manifest
   set regardless of a file's own `type` attribute - so every single
   `getFrameworkHalManifest()` call anywhere in the system failed with
   `-22`, forever, because one bad fragment poisons the whole directory's
   parse. `recovery/root/system/etc/vintf/manifest/` now ships harmless
   zero-HAL replacements (`<manifest version="1.0" type="framework">`) at
   those exact two paths - this tree's own `type 0x2` fragment's cpio
   entries win the directory-merge over stock's `type 0x1` copies (same
   "later fragment wins on a path collision" mechanism used throughout
   this tree already), which was enough: `keystore2`/`vendor.keymint-
   mitee` both settled to `running` (never `restarting`) and TWRP reached
   its actual home screen.

One easy-to-hit gotcha discovered along the way, unrelated to any of the
above but worth remembering: `adb reboot recovery` (and TWRP's own
`Reboot > Recovery`) sets the BCB (`/dev/block/by-name/misc`, first 32
bytes = `boot-recovery`) so the *next* power-on also goes to recovery,
even a plain `adb reboot` or physically power-cycling with no button
combo held. If normal boot ever seems to have broken again right after
testing recovery, check this before assuming a real regression:
```
adb shell "dd if=/dev/block/by-name/misc bs=1 count=64 2>/dev/null | xxd"
adb shell "dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=64"
```

HOW TO COMPILE:
```
source build/envsetup.sh
lunch twrp_taiko-eng
mka vendorbootimage
```
`$OUT/vendor_boot.img` is ready to flash as-is; no post-processing step.

One caveat that has bitten this tree repeatedly: deleting files from
`recovery/root/` does not remove copies the build already staged under
`$OUT/target/product/taiko/recovery/root/`, so a stale ramdisk can silently
keep shipping them (this is how the removed lib/modules first blew past the
64MB budget). When changing what recovery/root contains, clear the staged
copy and the two intermediates before rebuilding:
```
rm -rf $OUT/recovery/root/<path you removed>
rm -f $OUT/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp
rm -f $OUT/obj/PACKAGING/vendor_ramdisk_fragments_intermediates/recovery.cpio.lz4
```
