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

LOCAL_PATH := device/xiaomi/taiko

# Dynamic
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# V A/B
ENABLE_VIRTUAL_AB := true
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/compression.mk)

# Bootctrl
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-mtkimpl \
    android.hardware.boot@1.2-mtkimpl.recovery

PRODUCT_PACKAGES_DEBUG += \
    bootctrl

# Fastbootd
PRODUCT_PACKAGES += \
    fastbootd \
    android.hardware.fastboot@1.0-impl-mock

# Health Hal
PRODUCT_PACKAGES += \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service
    
# AB
AB_OTA_UPDATER := true

# A/B
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    product \
    system \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    vendor \
    vendor_boot
    
AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true

# VNDK
PRODUCT_TARGET_VNDK_VERSION := 32

# API
PRODUCT_SHIPPING_API_LEVEL := 32

PRODUCT_PACKAGES_DEBUG += \
    update_engine_client

PRODUCT_PACKAGES += \
    otapreopt_script \
    cppreopts.sh \
    update_engine \
    update_verifier \
    update_engine_sideload

# MTK PlPath Utils
PRODUCT_PACKAGES += \
    mtk_plpath_utils.recovery

# Additional binaries & libraries needed for recovery
#
# libpuresoftkeymasterdevice used to be listed here too. It is redundant:
# TWRP already relinks that exact path itself, at
# bootable/recovery/prebuilt/Android.mk:216, inside the TW_INCLUDE_CRYPTO_FBE
# block - and TW_INCLUDE_CRYPTO_FBE is not something this device sets, it is
# derived from our TW_INCLUDE_CRYPTO := true by bootable/recovery/Android.mk:339.
# prebuilt/Android.mk is included from Android.mk:737, i.e. after that
# assignment, so the block is live for us. Listing it again fed the identical
# $(TARGET_OUT_SHARED_LIBRARIES)/libpuresoftkeymasterdevice.so string into
# RECOVERY_LIBRARY_SOURCE_FILES twice (via prebuilt/Android.mk:332), which
# then reaches LOCAL_REQUIRED_MODULES twice at prebuilt/Android.mk:432.
# That duplicate is the prime suspect for BUILD_BROKEN_DUP_RULES in
# BoardConfig.mk - see the note there.
#
# libion has to stay: nothing in TWRP relinks it, so this is the only thing
# putting it in the ramdisk.
TARGET_RECOVERY_DEVICE_MODULES += \
    libion

TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so

# Vendor ramdisk
#
# NOTE: both of these currently go nowhere, and are kept only so this stops
# being rediscovered. TARGET_COPY_OUT_VENDOR_RAMDISK feeds the PLATFORM
# fragment that build/make/core/Makefile generates - and build/tasks/
# vendor_boot.mk repoints INTERNAL_VENDOR_RAMDISK_TARGET at
# prebuilt/vendor_ramdisk.cpio.lz4, so the generated one is built and then
# discarded. The prebuilt already carries its own
# first_stage_ramdisk/fstab.mt6789, byte-identical to the file here, and no
# fstab.emmc at all (taiko is UFS-only - see the mmcblk0boot0 note in
# recovery/root/init.recovery.mt6789.rc).
#
# Left in place rather than deleted because they cost nothing and become
# load-bearing again the moment that INTERNAL_VENDOR_RAMDISK_TARGET
# override is dropped, which is exactly when a missing first-stage fstab
# would be at its most expensive to debug.
PRODUCT_COPY_FILES += \
     device/xiaomi/taiko/fstab.emmc:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.emmc \
     device/xiaomi/taiko/fstab.mt6789:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.mt6789

