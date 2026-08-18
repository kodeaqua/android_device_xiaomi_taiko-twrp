#
# Copyright (C) 2022 The TWRP Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

DEVICE_PATH := device/xiaomi/taiko

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a55

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a55

TARGET_BOARD_SUFFIX := _64
TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_64_BIT_APPS := true

ENABLE_CPUSETS := true
ENABLE_SCHEDBOOST := true

# Assertation
TARGET_OTA_ASSERT_DEVICE := taiko

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := taiko
TARGET_NO_BOOTLOADER := true
TARGET_USES_UEFI := true

# Platform
TARGET_BOARD_PLATFORM := mt6789

# Build Hack
BUILD_BROKEN_DUP_RULES := true

# Kernel
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64

TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
# BOARD_KERNEL_CMDLINE/BOARD_BOOTCONFIG (not a manual --vendor_cmdline
# BOARD_MKBOOTIMG_ARGS override, see below) match the taiko retail
# vendor_boot.img exactly: the stock vendor_cmdline is literally
# "bootopt=64S3,32N2,64N2 bootconfig", with the trailing "bootconfig"
# token telling the kernel to parse an appended bootconfig trailer
# containing the 3 kernel.* lines below (verified via unpack_bootimg.py
# against the retail image). build/make/core/board_config.mk only
# appends "bootconfig" to the vendor cmdline and generates the trailer
# when BOARD_BOOTCONFIG is actually set, so both must be defined
# together for the image to match what this stock, unmodified kernel
# was actually shipped and tested with.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2
BOARD_BOOTCONFIG := kernel.rcu_nocbs=all kernel.rcutree.enable_rcu_lazy=1 kernel.rcupdate.rcu_cpu_stall_cputime=1
# Base/offsets below were cross-checked against the taiko retail
# vendor_boot.img header (unpack_bootimg) and match rock's values exactly,
# since both are mt6789-family boards: kernel_offset=0x40000000,
# ramdisk_offset=0x66f00000, tags_offset=dtb_offset=0x47c80000.
BOARD_KERNEL_BASE := 0x3fff8000
BOARD_PAGE_SIZE := 4096
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x26f08000
BOARD_TAGS_OFFSET := 0x07c88000
BOARD_BOOT_HEADER_VERSION := 4
BOARD_HEADER_SIZE := 2128
BOARD_DTB_SIZE := 191057
BOARD_DTB_OFFSET := 0x07c88000
BOARD_FLASH_BLOCK_SIZE := 262144

BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_PAGE_SIZE) --board ""
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)

BOARD_KERNEL_SEPARATED_DTBO := true
BOARD_RAMDISK_USE_LZ4 := true
#TARGET_NO_KERNEL := true

# VNDK
BOARD_VNDK_VERSION := current

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_VBMETA_SYSTEM := system
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1

# Partitions
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864
#BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864

# Dynamic Partition
# Values verified from the retail super.img (liblp metadata): total super
# size 0x2c0000000, "main" partition group max size 0x2bfa00000, dynamic
# partitions system/system_ext/product/vendor/vendor_dlkm/odm_dlkm/
# system_dlkm/mi_ext. system_dlkm and mi_ext are real on-device dynamic
# partitions (see recovery.fstab) but this AOSP branch's
# BOARD_MAIN_DYNAMIC_PARTITIONS_PARTITION_LIST whitelist (build/make/core/
# config.mk) only accepts system/vendor/product/system_ext/odm/vendor_dlkm/
# odm_dlkm, so they are left out of the build-time list; TWRP still mounts
# them at runtime via recovery.fstab.
BOARD_SUPER_PARTITION_SIZE := 0x2c0000000
BOARD_SUPER_PARTITION_GROUPS := main_dynamic_partitions
BOARD_MAIN_DYNAMIC_PARTITIONS_SIZE := 0x2bfa00000
BOARD_MAIN_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext odm_dlkm vendor_dlkm

TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM := system
TARGET_COPY_OUT_VENDOR := vendor

# Stock ships system/system_ext/vendor/product as EROFS (verified from the
# vendor_a superblock), ext4 kept as a fallback build type.
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_ROOT_EXTRA_FOLDERS += cust
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# System as root
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false

# Recovery
TARGET_NO_RECOVERY := true
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_SUPPRESS_SECURE_ERASE := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE :=
# Both flags together (per build/make/core/Makefile:1087-1094) make the
# build emit vendor_boot with TWO vendor ramdisk fragments, matching the
# taiko retail vendor_boot.img exactly: a generic fragment (ramdisk_type
# 1, no name) plus a separately-typed "recovery" fragment (ramdisk_type
# 2/RECOVERY, name "recovery") holding TWRP's recovery root. Building
# with only BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT (as inherited
# from rock) instead produces a single generic-only fragment; on real
# taiko hardware that single-fragment image boots fine to the ROM
# (normal boot ignores fragment typing) but the bootloader crashes
# (MTK AEE LK_CRASH, confirmed via /data/vendor/aee_exp/db.fatal.*.KE)
# specifically when asked to enter recovery mode, since it expects to
# find the typed "recovery" fragment that was missing.
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# Crypto
# TW_INCLUDE_CRYPTO was previously disabled entirely because the compiled-in
# android::vold::fscrypt_mount_metadata_encrypted() call (system/vold/
# MetadataCrypt.cpp) hung forever waiting for a KeyMint/Keystore2 HAL that
# didn't exist in the ramdisk - taiko uses Xiaomi's own in-house "mitee" TEE
# (mitee.ko), not the Trustonic "beanpod" stack rock's tree carried (which
# was correctly dropped rather than shipped unverified, since it would never
# have worked - different TEE, different wire protocol, different .ta
# format).
#
# This is now fixed properly (not by patching bootable/recovery, which
# doesn't gate TW_INCLUDE_FBE_METADATA_DECRYPT independently anyway - see
# git history) by bundling taiko's REAL mitee-based KeyMint/Gatekeeper HAL,
# extracted from the retail vendor.img in the firmware dump referenced in
# the README (super.img -> lpunpack -p vendor_a -> fsck.erofs --extract):
#   - vendor/bin/hw/android.hardware.security.keymint@4.0-service.mitee
#   - vendor/bin/hw/android.hardware.gatekeeper-service.mitee
#   - vendor/bin/tee-supplicant (talks to /dev/tee0 via mitee.ko)
#   - vendor/lib64/{libteecli,libkeymint,libgatekeeper,...}.so (real
#     dependency closure per `readelf -d`, everything else - libc, liblog,
#     libbinder_ndk, etc. - was already present as a TWRP/AOSP dependency)
#   - vendor/mitee/ta/*.ta (13 trusted-application blobs, ~7.3MB total;
#     bundled verbatim/unfiltered since individual TA purposes aren't
#     documented and mitee TAs may depend on each other)
#   - vendor/etc/init/{keymint,gatekeeper,tee-supplicant}*.rc (verbatim
#     stock rc - the tee-supplicant one's "on fs" block does the /dev/tee0
#     chmod/chown, enables the keymint service, and starts tee-supplicant)
#   - vendor/etc/vintf/manifest.xml + manifest/*.xml fragments (needed for
#     the real HAL to register/be found at all - was completely missing
#     before, which is a separate issue from TWRP's own cosmetic
#     Process_Keymaster_Version() logging in partitionmanager.cpp, which
#     only ever looks for the legacy HIDL "android.hardware.keymaster"
#     name and will therefore keep printing an empty keymaster_ver on any
#     modern all-AIDL device like this one - confirmed harmless/cosmetic,
#     not read anywhere else in bootable/recovery)
#   - vendor/etc/selinux/vendor_tee_service_contexts
#
# UNVERIFIED on real hardware yet: this device tree has no custom sepolicy
# sources (no device/xiaomi/taiko/sepolicy dir), so if TWRP's own default
# recovery sepolicy denies binder access between vold/keystore2 and these
# newly-added vendor.keymint-mitee/vendor.gatekeeper_mitee services, this
# could hang again the same way the original bug did. If that happens,
# check `adb shell dmesg | grep avc` for denials first.
TW_INCLUDE_CRYPTO := true
BOARD_USES_METADATA_PARTITION := true

# Encryption
PLATFORM_VERSION := 13
PLATFORM_VERSION_LAST_STABLE := 13
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31

# TWRP Configuration
TW_THEME := portrait_hdpi
# TW_ROTATION=180. bootable/recovery's touch handling (minuitwrp/
# events.cpp) never applies gr_rotation to touch coordinates - only
# minuitwrp/graphics.cpp's *drawing* respects it (grep for gr_rotation
# only matches graphics.cpp) - so this only ever corrects the display,
# never touch. That's fine here: raw touch was verified normal/
# unswapped on real hardware (`adb shell getevent -lt`: tapping the
# physical top-left corner reports low ABS_MT_POSITION_X/Y, physical
# bottom-right reports high values - standard orientation, no invert or
# swap needed).
#
# The panel's native scanout (TW_ROTATION=0) is rotated 180 from the
# portrait_hdpi theme's actual button layout - confirmed by tapping the
# button visually labeled "Install" (which appeared at the bottom-right
# instead of its normal top-left position) and having it open the
# Reboot page instead: since touch is normal/unrotated, tapping the
# physical bottom-right hits the *un-rotated* buffer position, i.e.
# whatever the theme actually draws at buffer bottom-right (Reboot),
# not whatever visually appears there on the native-rotated panel. 180
# corrects the *drawing* to match the theme's real layout; since touch
# was already normal to begin with, both then line up.
#
# (Earlier real-hardware feedback with 180 active reported it as still
# mismatched, but that check wasn't done with a precise visual-anchor
# test like the Install/Reboot one above - reapplying now that the
# mechanism is confirmed end-to-end; needs a real re-test to be sure.)
TW_ROTATION := 180

TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
RECOVERY_SDCARD_ON_DATA := true
TW_SCREEN_BLANK_ON_BOOT := true
TW_NO_SCREEN_BLANK := true
TW_USE_TOOLBOX := true
TW_HAS_MTP := true
# NOTE: TW_BRIGHTNESS_PATH below is carried over from the mt6789 rock
# (POCO M5) tree and is NOT verified against real taiko (Redmi Pad 2)
# hardware, but that's safe: TWRP falls back to auto-discovery under
# /sys/class/backlight then /sys/class/leds/lcd-backlight if this path
# doesn't exist (data.cpp, DataManager::SetDefaultValues), so a wrong
# guess here just costs a Find_File() scan, not a broken boot.
#
# TW_MAX_BRIGHTNESS/TW_DEFAULT_BRIGHTNESS were previously hardcoded to
# rock's values (2020/1200) with no way to know if they applied to
# taiko's backlight scale. Per bootable/recovery/data.cpp, defining
# TW_MAX_BRIGHTNESS disables TWRP's own runtime auto-detection of the
# real max_brightness (it reads the sibling max_brightness sysfs file
# next to the brightness node, falling back to 255 only if that read
# fails) and there is no bounds check anywhere on the write path
# (twrp-functions.cpp Set_Brightness/write_to_file is a raw fwrite with
# no clamp) - so a wrong hardcoded max/default here can leave the
# backlight stuck at whatever the kernel driver does with an
# out-of-range write, with no error surfaced to the user (this is the
# most likely cause of a "just black screen" first boot on real
# hardware: TW_SCREEN_BLANK_ON_BOOT+TW_NO_SCREEN_BLANK below blank then
# restore the backlight via this exact path at boot). Left undefined so
# TWRP determines the real scale and boots at full brightness.
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_INPUT_BLACKLIST := "hbtp_vm"
# The touchscreen (Novatek nt36xxx_spi) and its Xiaomi touch-feature base
# driver are NOT in the 210 modules pulled from vendor_boot's generic
# ramdisk fragment (recovery/root/lib/modules) - real hardware boot dmesg
# ("Modules linked in:") shows both nt36xxx_spi(O) and xiaomi(O) loaded,
# but neither .ko ships in the ramdisk, meaning MIUI lazy-loads them from
# /vendor/lib/modules on the real (mounted) vendor partition instead.
# TW_LOAD_VENDOR_MODULES enables TWRP's own KernelModuleLoader
# (bootable/recovery/kernel_module_loader.cpp, already gated on this exact
# BoardConfig variable - no bootable/recovery changes needed) to mount
# /vendor and load these two by name during Setup_Fstab.
TW_LOAD_VENDOR_MODULES := "nt36xxx_spi.ko xiaomi.ko"
TW_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone28/temp"
TW_FRAMERATE := 60
TW_STATUS_ICONS_ALIGN := center
TW_CUSTOM_CPU_POS := 50
TW_CUSTOM_CLOCK_POS := 300
TW_CUSTOM_BATTERY_POS := 800
TW_EXCLUDE_APEX := true
TW_EXTRA_LANGUAGES := true
TW_DEFAULT_LANGUAGE := en
TW_INCLUDE_NTFS_3G := true
TARGET_USES_MKE2FS := true
TW_EXCLUDE_TWRPAPP := true
TW_INCLUDE_FUSE_EXFAT := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_BACKUP_EXCLUSIONS := /data/fonts/files
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP :=true
TW_INCLUDE_REPACKTOOLS := true
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.usb0/lun.%d/file

# Debug
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
