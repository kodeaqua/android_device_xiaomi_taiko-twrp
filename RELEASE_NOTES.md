# TWRP 3.7.1_12-0 for Xiaomi Redmi Pad 2 (taiko) — v1.0.1 (unreleased)

Follow-up to v1.0.0, from a field report of a unit with **no touch at all**
and an unusably laggy USB mouse. Both are fixed here. Neither fix is verified
on the affected hardware yet — see *Still open*.

### Touch on Tianma and Huaxing units

v1.0.0 shipped one digitiser driver and one firmware blob, both for the BOE
panel. taiko has three panel variants and stock loads a driver for each on
every unit. On a Tianma or Huaxing unit v1.0.0 therefore had **no working
digitiser at all** — not slow, absent — because the driver either was not
present or requested a firmware file that was not in the ramdisk, with the
real `/vendor` already unmounted by then.

Added, all byte-identical to `OS3.0.304.0.WOVMIXM`:

- `focaltech_tp.ko` — FocalTech FT8205P, the Huaxing panel's digitiser
- `xiaomi_headset_touch_notifier.ko` — its one dependency not already in the
  factory ramdisk fragment
- `novatek_ts_fw_tm.bin` — Novatek NT36536, the Tianma panel's firmware
- `focaltech_ts_fw_huaxing.bin`, plus the `novatek_ts_mp_*` / `focaltech_mp_*`
  self-test blobs for completeness

`init.recovery.mt6789.rc` now insmods all four modules in dependency order
(`insmod` does not resolve `depends=` the way stock's `modprobe` does), and
`TW_LOAD_VENDOR_MODULES` lists all four as the fallback path. See the new
*Panel / digitiser variants* section in the README for the full mapping.

### USB mouse lag

An attached mouse rendered at 2 FPS. `loopTimer()` gives the input queue a
catch-up window before drawing, and that window was a flat 500 ms whenever an
event had just arrived. A mouse reports at 125–1000 Hz, so the condition was
true on essentially every iteration for as long as the pointer moved, and
`TW_FRAMERATE` was never reached on that path at all. Capped at two frame
times, i.e. a 30 FPS floor at `TW_FRAMERATE=60`.

Also fixed an inverted comparison in `MouseCursor::SetRenderPos` that flagged
a move only when the position had *not* changed, so a freshly attached mouse
drew no cursor until it was first moved.

Both are in `bootable/recovery`, not the device tree.

### Cleanup

Removed four blobs nothing can reach. `android.hardware.gatekeeper@1.0-impl.so`,
`gatekeeper.default.so` and `libSoftGatekeeper.so` were the libraries behind
the `gatekeeper-1-0` service v1.0.0 deleted — the binary went, the libraries
stayed. `libdrm.so` was never referenced by anything in the ramdisk, and AOSP's
own libdrm is `recovery_available: true`, so TWRP already ships one at
`/system/lib64`, which `LD_LIBRARY_PATH` searches first.

Established by walking `DT_NEEDED` transitively from the only three things
init starts — the mitee keymint and gatekeeper services and `tee-supplicant`.
The same walk confirms the remaining 15 bundled objects are all reachable and
that every external dependency they name is relinked into `/system/lib64` by
TWRP itself (`bootable/recovery/prebuilt/Android.mk` 194-217), so the
decryption failure below is **not** a missing library. That relink block sits
under `TW_INCLUDE_CRYPTO_FBE`, which this device never sets directly — it is
derived from our `TW_INCLUDE_CRYPTO := true` at
`bootable/recovery/Android.mk:339`, and `prebuilt/Android.mk` is included
after that assignment (`Android.mk:737`), so the block is live for taiko.

### Build config

Two pieces of dead configuration removed, both established by reading the
build and mount code rather than by running anything.

`device.mk` listed `libpuresoftkeymasterdevice` in both
`TARGET_RECOVERY_DEVICE_MODULES` and
`TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES` while TWRP already relinks the
identical path at `bootable/recovery/prebuilt/Android.mk:216`. The device
list is folded into the same `RECOVERY_LIBRARY_SOURCE_FILES` variable at
`prebuilt/Android.mk:332`, so the string landed in it twice and reached
`LOCAL_REQUIRED_MODULES` twice at `prebuilt/Android.mk:432`. Only the
duplicate is gone; `libion`, which nothing in TWRP relinks, stays in both
lists. `BUILD_BROKEN_DUP_RULES := true` is gone with it: a full
`mka vendorbootimage` completes clean without the hack, with no
duplicate-rule diagnostic in the log.

`recovery.fstab` carried `avb_keys=/avb/{q,r,s}-gsi.avbpubkey` on the four
`system` / `system_ext` lines. Inert twice over: TWRP reads this file with
its own `TWPartition::Process_Fstab_Line`, which does not know the token and
drops it silently, and `fs_mgr` — which does parse it
(`fs_mgr_fstab.cpp:285`) — tests `fs_mgr_flags.avb` first and only reaches
the standalone `avb_keys` branch when that is unset (`fs_mgr.cpp:1450`,
`1466`). These lines set it via `avb=vbmeta_system`. No `/avb` directory
exists in either ramdisk fragment either, and Q/R/S-era GSI keys would not
cover a current GSI.

### Cross-checked against other taiko / mt6789 trees

Compared against MySelly's LineageOS `taiko` device and vendor trees, the
`xiaomi-mt6789-devs` `yunluo` tree, and muhammadrafiasyddiq's TWRP trees for
`rock` (also mt6789) and `emerald`. Most of what came out of it was
confirmation; three things were not.

Removed `start vendor.vibrator-default` from `on boot`. Nothing anywhere in
the image defines that service — TWRP installs no vibrator `.rc`, the factory
PLATFORM fragment has none, and AOSP's
`android.hardware.vibrator-service.example` is `vendor: true` without
`recovery_available`, so neither its binary nor its `.rc` is ever present.
This is also why `TW_SUPPORT_INPUT_AIDL_HAPTICS`, which `emerald` sets, is
deliberately left off here: `minuitwrp`'s `vibrate()` goes through the
blocking `AServiceManager_getService()`.

Annotated the two `PRODUCT_COPY_FILES` entries that put `fstab.emmc` and
`fstab.mt6789` into `TARGET_COPY_OUT_VENDOR_RAMDISK`. They currently reach
nothing: `build/tasks/vendor_boot.mk` repoints
`INTERNAL_VENDOR_RAMDISK_TARGET` at the prebuilt fragment, which carries its
own byte-identical `first_stage_ramdisk/fstab.mt6789` and no `fstab.emmc` at
all. Left in place rather than deleted — they become load-bearing again the
moment that override goes, and a missing first-stage fstab is an expensive
thing to debug.

Corrected the `vendor_boot.mk` header, which still claimed `recovery/root`
ships no `lib/modules`. It ships four, as of the touch fix above.

Two checks that came back clean and are worth recording so they are not
redone. The touch modules' dependency closure was verified directly against
the extracted prebuilt fragment: all nine modules the four `.ko` name are
among its 210, and `modules.load.recovery` loads them at lines 8-197, before
this tree's `insmod`s run. And `boot-hal-1-2` / `health-hal-2-1`, which look
like stale HIDL-era names next to the factory fragment's own
`vendor.boot-default` / `vendor.health-default`, are TWRP's own services from
`bootable/recovery/etc/init/`, valid under `AB_OTA_UPDATER := true`.

`rock` and `emerald` also set `TW_INCLUDE_CRYPTO_FBE` and
`TW_INCLUDE_FBE_METADATA_DECRYPT` explicitly. Both are redundant in this
fork: the first is derived from `TW_INCLUDE_CRYPTO`
(`bootable/recovery/Android.mk:339`) and the second is not independently
gated at all — `-DTW_INCLUDE_FBE_METADATA_DECRYPT` is added unconditionally
inside the same `TW_INCLUDE_CRYPTO` block, at `Android.mk:358`.

### `twrp.flags` fixes

This tree already had `recovery/root/system/etc/twrp.flags`, so most of what
the reference trees offer here was already covered — `boot`, `vendor_boot`,
both slotted vbmeta partitions and the removable-storage entries all had
sensible flags. Five real defects surfaced by comparing it against the
`twrp.flags` in `Shakib-BD/recovery_xiaomi_rock`, a Xiaomi mt6789 device with
a nearly identical partition table:

- The `/system_ext` entry had its `flags=` stranded on the following line, so
  it parsed as an entry with no flags plus one junk line. Joined.
- `/system_image`, `/vendor_image` and `/product_image` named
  `/dev/block/mapper/<part>_a` directly. That backs up and flashes the A copy
  regardless of which slot is active — wrong, and silently so, on slot B.
  Now `slotselect` against the bare mapper name, matching how this same file
  already handles `boot` and the vbmetas.
- `system_ext`, `vendor_dlkm`, `odm_dlkm`, `system_dlkm` and `mi_ext` had no
  image entry at all, so they could be neither backed up nor flashed.
- `/logo` pointed at `/dev/block/by-name/logo_a`. Stock addresses `logo` by
  bare name and does not mark it `slotselect`, so the suffix was invented.
- `/lk1` pointed at a `by-name/lk1` that does not exist on taiko —
  `recovery.fstab` has `lk` at `/bootloader` and `lk2` at `/bootloader2`.
  Repointed at `/bootloader` so the display name lands on a real partition.

`dtbo` and `vbmeta` also gained `backup=1` (`dtbo` gained `flashimg=1` too);
both were reachable but not backupable.

Also removed a byte-identical duplicate `/vendor_boot` line from
`recovery.fstab` — `Process_Fstab` pushes one partition per line without
checking for a repeated mount point, so it produced two identical GUI rows.
The two `/bootloader2` lines were left alone: they name different block
devices (`lk2` and `bootloader2`), only one of which exists on any board, and
there is no way to tell from here which one taiko has.

**None of this is verified on hardware.**

### Corrected: what unmounts persist

The `check` flag was never the reason persist gets mounted and dropped again
early in boot. `check` reaches `Check_FS_Type`, which identifies the
filesystem with a blkid probe and mounts nothing (`partition.cpp:2217`). The
real cause is `Update_Size`, which mounts every partition with
`Can_Be_Mounted` set just to measure it (`partition.cpp:3084-3087`), run
across the whole table by the "Updating partition details..." pass. So
dropping `check` would not have helped, and the sleep-then-mount workaround
in `tee-supplicant.rc` stays. TWRP's one hardcoded persist special case —
the `/persist/time/` clock fixup at `partition.cpp:660` — does not apply
here either; it keys on the mount point being exactly `/persist`, and both
fstabs use `/mnt/vendor/persist`.

### Still open

- **Decryption failure on the same reporter's device**, which is running a
  GSI. Not reproduced and not diagnosed — needs `/tmp/recovery.log`,
  `dmesg | grep -iE "mitee|avc"` and `logcat | grep -iE "keymint|vold"` from
  that unit, plus its GSI build, its HyperOS base version, and whether it has
  a lock screen credential set. Note that the credential-protected layer
  needing the lock screen credential is expected behaviour, not this bug.
- **Partition tools: `TW_INCLUDE_LPTOOLS` yes, `TW_ENABLE_ALL_PARTITION_TOOLS`
  probably not.** The budget is now measured rather than guessed: the built
  `vendor_boot.img` is 60.69MB of the 64MB partition, leaving 3.31MB.
  `TW_ENABLE_ALL_PARTITION_TOOLS` pulls `lpdump` in as well, and `lpdump`
  drags `libprotobuf-cpp-full.so` plus two `liblpdump*` libraries behind it —
  plausibly more than the headroom. `TW_INCLUDE_LPTOOLS` on its own is a
  single small binary and is the safer half. Transsion's mt6789 tree makes
  exactly that split, setting `TW_INCLUDE_LPTOOLS := true` alongside
  `TW_EXCLUDE_LPDUMP := true`. Still unset here; needs a build to confirm
  either way.
- **`TW_MAX_BRIGHTNESS` is unset, deliberately, but unverified.** Without it
  TWRP reads `max_brightness` next to `TW_BRIGHTNESS_PATH` and falls back to
  255 if that node is missing (`bootable/recovery/data.cpp:867-889`), which
  is more correct than hardcoding — provided
  `/sys/class/leds/lcd-backlight/max_brightness` exists on taiko. Worth a
  single `cat` on the next device that boots this. `rock` and `emerald`
  hardcode 2020/1200.
  because it cannot be verified without a build.

---

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
