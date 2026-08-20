# Use the device's real, factory vendor ramdisk as vendor_boot's PLATFORM
# ramdisk.
#
# Why this exists at all (full story in README's "vendor_boot.img" section):
# this board's bootloader loads the vendor ramdisk's PLATFORM (type 0x1)
# fragment BY ITSELF for a normal Android boot - it is only concatenated
# with the RECOVERY (type 0x2) fragment when booting recovery. That
# PLATFORM fragment therefore has to be a complete first-stage rootfs, and
# on this device the factory one is ~70MB of MIUI's own bootstrap content
# (its init variant, linkerconfig, sepolicy, prop.default, res/, the 210
# kernel modules, ...). Nothing this tree can build reproduces that: the
# best AOSP-13 vendor ramdisk we can generate is well under half the size
# and missing all of it, and flashing one produces a kernel panic
# ("Unable to mount root fs on /dev/ram") the moment the bootloader hands
# that fragment to the kernel on its own. prebuilt/vendor_ramdisk.cpio.lz4
# is that factory fragment, extracted once from this device's own shipped
# vendor_boot.img and committed as a prebuilt because the build cannot
# regenerate it.
#
# How it is wired in: build/make/core/Makefile always generates the
# PLATFORM ramdisk itself (INTERNAL_VENDOR_RAMDISK_TARGET, mkbootfs over
# $(TARGET_VENDOR_RAMDISK_OUT)) and passes it to mkbootimg as
# --vendor_ramdisk; the official BOARD_VENDOR_RAMDISK_FRAGMENT.*.PREBUILT
# mechanism only covers the *extra* fragments, so it cannot supply this
# one. What it can do is repoint the variable: this file is pulled in by
# `-include $(sort $(wildcard device/*/*/build/tasks/*.mk))` at the very
# end of core/Makefile - after every image rule is defined - and make
# expands recipe bodies at execution time, so reassigning the variable
# here is what the mkbootimg command line ends up using. The generated
# ramdisk is still built (it stays a prerequisite, recorded earlier with
# the old value); it simply goes unused, which also keeps the dependency
# graph intact.
#
# The RECOVERY fragment is untouched and still comes from this tree's own
# build on every compile, so TWRP itself is built normally - only the
# PLATFORM half is prebuilt. In recovery mode both fragments are merged, so
# anything recovery/root duplicates from the factory fragment only eats into
# the fixed 64MB BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE budget (which
# core/Makefile's assert-max-image-size enforces right after mkbootimg
# runs). That is why recovery/root/lib/modules holds exactly four .ko and
# not a mirror of the factory set: the factory fragment's 210 modules
# include every dependency those four name - miev, hqsysfs,
# mediatek_drm_v1, mtk_disp_notify, mtk_panel_ext, xiaomi_usb_touch_notifier
# and all three panel-o84-* variants - and init loads them from
# modules.load.recovery lines 8-197, well before the insmods in
# init.recovery.mt6789.rc run. What the factory set does NOT contain is any
# digitiser driver at all (verified: 210 .ko, no nt36xxx_spi, no
# focaltech_tp, no xiaomi.ko) or any touch firmware, which is why those have
# to be carried here.

ifeq ($(TARGET_DEVICE),taiko)

TAIKO_PREBUILT_VENDOR_RAMDISK := device/xiaomi/taiko/prebuilt/vendor_ramdisk.cpio.lz4

# Rebuild vendor_boot.img if the prebuilt changes (the recipe references it,
# but the recorded prerequisite still points at the generated ramdisk).
$(INSTALLED_VENDOR_BOOTIMAGE_TARGET): $(TAIKO_PREBUILT_VENDOR_RAMDISK)

INTERNAL_VENDOR_RAMDISK_TARGET := $(TAIKO_PREBUILT_VENDOR_RAMDISK)

endif
