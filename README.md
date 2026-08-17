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
TOUCH — carried over from rock, UNVERIFIED (see caveats)
DECRYPTION — UNVERIFIED, likely needs more work (see caveats)

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
  bundle would not have worked and was removed rather than shipped
  unverified. Only the generic AOSP software gatekeeper is left in place.
  Getting FBE decryption working needs the real keymint/gatekeeper HAL
  pulled from a rooted taiko's `/vendor` (its filesystem is EROFS; this
  environment had no erofs-utils/root available to unpack it).
- **Touch firmware**: rock's `focaltech_*`/`nt36672c_*` touch firmware
  files were removed since taiko's module list doesn't reference either
  driver — untested whether taiko's touch panel needs any firmware blob at
  all bundled in recovery.
- **Brightness/thermal paths**: `TW_BRIGHTNESS_PATH`, `TW_MAX_BRIGHTNESS`,
  `TW_CUSTOM_CPU_TEMP_PATH` are carried over from rock unverified; confirm
  against real sysfs on-device.
- **Theme/orientation**: `TW_THEME := portrait_hdpi` kept as-is; taiko's
  11" 2000x1200 panel is untested with this theme.

HOW TO COMPILE:
```
source build/envsetup.sh
lunch twrp_taiko-eng
mka vendorbootimage
```
