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
# PLATFORM half is prebuilt. Note that recovery/root deliberately ships no
# lib/modules: the factory fragment already carries all 210 .ko files, and
# in recovery mode both fragments are merged, so a second copy would only
# eat into the fixed 64MB BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE budget
# (which core/Makefile's assert-max-image-size enforces right after
# mkbootimg runs).

ifeq ($(TARGET_DEVICE),taiko)

TAIKO_PREBUILT_VENDOR_RAMDISK := device/xiaomi/taiko/prebuilt/vendor_ramdisk.cpio.lz4

# Rebuild vendor_boot.img if the prebuilt changes (the recipe references it,
# but the recorded prerequisite still points at the generated ramdisk).
$(INSTALLED_VENDOR_BOOTIMAGE_TARGET): $(TAIKO_PREBUILT_VENDOR_RAMDISK)

INTERNAL_VENDOR_RAMDISK_TARGET := $(TAIKO_PREBUILT_VENDOR_RAMDISK)

endif
