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
  hardware for freshly-formatted /data (see caveats: pre-existing stock-encrypted
  /data is blocked by KeyMint anti-rollback protection, not fixable from recovery)
NORMAL BOOT ("boot to System") — BROKEN by this tree's vendor_boot.img since the
  switch to typed vendor ramdisk fragments; TWRP/recovery itself unaffected. See
  "KNOWN ISSUE" section below before doing any more vendor_boot.img work.

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

## Caveats / follow-up work

- **TEE / decryption**: rock's tree bundled a Trustonic "beanpod" TEE stack
  (`teei_daemon`, `keymint-beanpod`, `/vendor/thh/ta/*`) into the recovery
  ramdisk for FBE password decryption. taiko's real kernel module list loads
  `mitee.ko` instead — Xiaomi's own in-house TEE, not Trustonic — so that
  bundle would never have worked (different wire protocol, different `.ta`
  format) and was correctly dropped rather than shipped unverified.
  Getting real FBE decryption needed taiko's own mitee-based KeyMint/
  Gatekeeper HAL, which was unavailable earlier for lack of erofs-utils/root
  to unpack the EROFS `vendor` partition — since resolved (`erofs-utils`
  built from source against this checkout's `external/erofs-utils`, and
  `lpunpack`/`simg2img` built from `system/extras/partition_tools` and
  `system/core/libsparse` respectively, all host tools already present in
  this AOSP tree). The real stack was extracted from the retail vendor.img
  (`super.img` → `simg2img` → `lpunpack -p vendor_a` → `fsck.erofs
  --extract`) and bundled verbatim:
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
  `/proc/mounts`). **Pre-existing stock-encrypted `/data`** (i.e. the
  metadata-encryption key created back when the device still ran real
  HyperOS) is a different story: the mitee TA enforces KeyMint's
  anti-rollback protection (`CheckVersionInfo`/`LoadKey` in
  `mitee_keymaster_context.cpp`, per `/proc/mitee_log`) against the OLD
  key's embedded patchlevel, and none of this tree's own userspace HAL
  binaries actually call `ConfigureBootPatchlevel`/`ConfigureVendorPatchlevel`
  (confirmed: not a single binary in the real retail vendor.img calls these
  either) — the real boot-patchlevel state must be established via the
  bootloader→TEE verified-boot chain directly, which a custom/unverified
  boot chain like TWRP's can't satisfy. This looks like a hard, intentional
  security boundary, not a bug — don't spend more time on it without new
  information. The old generic AOSP software gatekeeper (from rock) is left
  in place alongside the real mitee one as a fallback; they register under
  different HAL namespaces (legacy HIDL vs. AIDL) so shouldn't conflict
  directly.
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

## KNOWN ISSUE — this tree's vendor_boot.img cannot boot to System

**Status: unsolved, do not attempt further live experiments without new
information (real MTK bootloader/LK source or documentation).** TWRP/recovery
mode itself is completely unaffected and works correctly with every commit on
`main` - this only affects booting the *same* `vendor_boot.img` into normal
Android (real ROM or GSI).

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

**Next steps for whoever picks this up**: the mechanism is now well
understood (see above) and the remaining problem is purely "fit real
first-stage content + this tree's recovery content in 64MB without breaking
either boot mode" - which needs either (a) much more careful, one-at-a-time
kernel-module dependency verification (ideally against real MTK/AOSP
documentation on which of the 210 modules are genuinely first-stage-critical
vs. loaded lazily later, not guessing from module *names*), or (b) shrinking
this tree's own recovery content significantly first (it's grown ~15MB since
the last time this worked, almost entirely from the mitee TA/crypto bundle -
see the DECRYPTION section above), to leave more headroom for real generic
content without needing to trim it as aggressively. Test recovery mode's
splash screen specifically after *any* kernel-module change, not just normal
boot - approach 5 above shows recovery can break in ways that have nothing
to do with the normal-boot mechanism at all.

HOW TO COMPILE:
```
source build/envsetup.sh
lunch twrp_taiko-eng
mka vendorbootimage
```
