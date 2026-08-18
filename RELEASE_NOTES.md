# TWRP 3.7.1_12-0 for Xiaomi Redmi Pad 2 (taiko) — v1.0.0

**Build date:** 2026-08-19
**Source commit:** `2404d58`
**TWRP base:** 3.7.1_12-0
**Platform:** MediaTek Helio G100 (mt6789)

First public release. Everything listed under *Verified working* was tested on
real hardware, not assumed from the build.

---

## Download

| File | Size | SHA256 |
|------|------|--------|
| `twrp-3.7.1_12-0-taiko-vendor_boot-20260819.img` | 64 MiB | `c056f27cc9d05be46ae94e369fc8c4976335771a6a7486af5a7836829cebdb25` |

MD5: `9149d3994889d546bafddcd39db5aa51`

> **This is a `vendor_boot` image, not a `boot` or `recovery` image.**
> Flashing it to the wrong partition will not work. See below.

---

## Install

Requires an unlocked bootloader. Your `boot`, `init_boot` and `super`
partitions are left alone — only `vendor_boot` is replaced.

```
adb reboot bootloader
fastboot flash vendor_boot twrp-3.7.1_12-0-taiko-vendor_boot-20260819.img
fastboot reboot recovery
```

To boot normally afterwards, just reboot. If the device keeps landing in
recovery instead of Android, the bootloader control block is still set — clear
it once from TWRP:

```
adb shell "dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=64"
```

This is normal Android behaviour, not a bug in this build: `adb reboot recovery`
and TWRP's own *Reboot → Recovery* both write `boot-recovery` into `misc`, which
also captures the next power-on.

### Reverting

Keep a copy of your stock `vendor_boot` before flashing:

```
adb shell "dd if=/dev/block/by-name/vendor_boot of=/tmp/vendor_boot-stock.img"
adb pull /tmp/vendor_boot-stock.img
```

---

## Verified working

- **Booting Android normally** from the same `vendor_boot` image
- **Touch** (Novatek `nt36xxx_spi`) — see *Known issues* for the warm-up delay
- **Display and rotation** (`TW_ROTATION := 180`)
- **Decryption (FBE + metadata encryption)** through the device's real
  mitee-based KeyMint/Gatekeeper HAL — including `/data` that a running Android
  system encrypted, not just data formatted by TWRP itself
- **Flashing ROMs and GSIs**, dynamic/logical partitions, `Wipe → Format Data`
- **MTP**, ADB sideload, backup and restore

---

## Changelog

### Decryption

- Fixed reading a `/data` that a real Android system encrypted. KeyMint kept
  returning `KEY_REQUIRES_UPGRADE` and then `INVALID_ARGUMENT` from the
  `upgradeKey()` that resolves it. Per `IKeyMintDevice.aidl`, `upgradeKey()`
  must fail with `INVALID_ARGUMENT` when any version recorded in the key is
  higher than the device's current value — and the recovery reported
  `OS_VERSION` 130000 (Android 13) while the system writing the key was
  Android 16 (160000). `PLATFORM_VERSION` is now 99. This is also why a
  TWRP-written key always re-read fine: 13 against 13.
- Brought up the real mitee KeyMint/Gatekeeper HAL: library `DT_SONAME`
  collisions, libc++/NDK ABI gaps, missing SELinux labels, missing VINTF
  manifest entries, and the persist-storage mount the TA depends on.

### Boot

- Fixed normal Android boot from this tree's `vendor_boot`. The bootloader
  loads the PLATFORM (type `0x1`) ramdisk fragment on its own for a normal
  boot, and only concatenates it with the RECOVERY fragment for recovery, so
  that fragment has to be a complete first-stage rootfs. The factory one is
  now shipped as a prebuilt and used verbatim; the RECOVERY half is still
  built from source every compile.
- Fixed TWRP hanging at the splash screen: two VINTF manifest files in the
  factory ramdisk declare `manifest version="9.0"`, which this tree's
  `libvintf` cannot parse. One unparseable fragment poisons every
  `getFrameworkHalManifest()` call, which is what crash-looped `keystore2`.
  Harmless zero-HAL replacements now override them.
- Removed a `wait /dev/block/mmcblk0boot0 2` inherited from MediaTek's
  eMMC-oriented template. This device is UFS-only and never creates that node,
  so it timed out in full on every boot — 2 seconds of init stalled behind it.

### Touch

- Touch now responds ~7 seconds sooner. The Novatek driver defers its firmware
  upload by a hardcoded ~14 s and reports nothing until it lands; that timer
  starts when the module loads. `nt36xxx_spi.ko` and `xiaomi.ko` live on
  `/vendor_dlkm`, which TWRP can only reach after mapping super, so the load
  happened at ~9.3 s. Both are now bundled in the ramdisk and loaded by init
  at ~2.1 s. Measured: first touch at ~16.1 s instead of ~23.3 s.

### Cleanup

- Removed a crash-looping `gatekeeper-1-0` service that could never register
  (no VINTF entry, and the shipped binary was not even executable), along with
  `start`/`stop` lines naming services that do not exist.
- Removed three legacy `voldmanaged=` fstab lines that TWRP turned into empty
  "Storage (0 MB)" entries in *Install → Select Storage*.
- Restored `mi_ext` as a plain fstab entry, fixing `Unable to unmap dynamic
  partitions` during `Format Data`.

### Build

- `mka vendorbootimage` now produces a directly flashable image with no helper
  script, wired through `device/xiaomi/taiko/build/tasks/vendor_boot.mk`. The
  image goes through the normal `assert-max-image-size` and AVB
  `add_hash_footer` steps.

---

## Known issues

- **Touch is unresponsive for roughly the first 16 seconds after boot.** The
  screen renders and the UI is live; only the digitiser is asleep. This is the
  Novatek driver's hardcoded ~14 s deferred firmware upload. It cannot be
  shortened further without patching a signed vendor kernel module, which
  would break its signature and risk losing touch entirely.
- **`Wipe → Format Data` occasionally fails** with `Unable to unmap dynamic
  partitions` or error 255. Retrying immediately succeeds. This predates the
  changes in this release and looks like a race while tearing down the mapped
  logical partitions.
- **`Failed to mount '/persist' (Device or resource busy)`** may appear after
  *Updating partition details*. Harmless and intermittent: TWRP can end up
  knowing this one partition under two mount points — `/mnt/vendor/persist`
  from `recovery.fstab` and `/persist` from the vendor fstab it re-parses off
  the real `/vendor` partition — and the second mount attempt returns `EBUSY`.
  Mounting persist earlier to avoid it was tried and reverted: it broke TEE
  bring-up and the watchdog force-rebooted the device.
- **`/data` decryption applies to the metadata/FBE layer.** Per-user
  credential-protected storage still needs the lock screen credential.

---

## Notes

- Built against the factory firmware `taiko_global_images_OS3.0.304.0.WOVMIXM`.
  The PLATFORM ramdisk fragment is taken verbatim from that release, so
  significantly newer or older firmware may behave differently.
- The recovery reports `ro.build.version.release=99` and a 2099 security patch
  date on purpose — this is what makes KeyMint accept keys written by any real
  Android version. It does not affect the installed OS.
- Source: <https://github.com/kodeaqua/device_xiaomi_taiko-twrp>
