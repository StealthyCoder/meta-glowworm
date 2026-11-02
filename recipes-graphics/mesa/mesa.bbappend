# SPDX-License-Identifier: MIT

# qcom-distro declares the opencl distro feature, which makes Mesa build LLVM, clang and Rust for
# Rusticl. Turnip (Vulkan) needs none of them. Set GLOWWORM_MESA_OPENCL = "1" to build Rusticl.
GLOWWORM_MESA_OPENCL ?= "0"

PACKAGECONFIG:remove:uno-q = "${@oe.utils.conditional('GLOWWORM_MESA_OPENCL', '1', '', 'opencl libclc gallium-llvm', d)}"
