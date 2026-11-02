# SPDX-License-Identifier: MIT

SUMMARY = "Glowworm: GPU userspace for the Adreno 702 on the Arduino UNO Q"
DESCRIPTION = "Mesa's Turnip Vulkan driver plus the Vulkan loader and tools, so the \
GPU can be probed with vulkaninfo and used by Vulkan compute workloads."
LICENSE = "MIT"

COMPATIBLE_MACHINE = "uno-q"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup

RDEPENDS:${PN} = " \
    mesa-vulkan-drivers \
    vulkan-loader \
    vulkan-tools \
"
