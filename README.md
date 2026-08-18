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
DECRYPTION — real mitee KeyMint/Gatekeeper HAL bundled, UNVERIFIED on real hardware yet (see caveats)

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

  `TW_INCLUDE_CRYPTO` is re-enabled accordingly. **Not yet verified on real
  hardware** — this device tree has no custom sepolicy sources, so if
  TWRP's own default recovery sepolicy denies binder access between vold/
  keystore2 and the newly-added `vendor.keymint-mitee`/
  `vendor.gatekeeper_mitee` services, this could hang the same way the
  original (now-fixed) splash-hang bug did. If so, check
  `adb shell dmesg | grep avc` for denials first. The old generic AOSP
  software gatekeeper (from rock) is left in place alongside the real
  mitee one as a fallback; they register under different HAL namespaces
  (legacy HIDL vs. AIDL) so shouldn't conflict directly.
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

HOW TO COMPILE:
```
source build/envsetup.sh
lunch twrp_taiko-eng
mka vendorbootimage
```
