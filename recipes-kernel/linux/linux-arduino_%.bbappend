# SPDX-License-Identifier: MIT

# Gives the PMIC RTC an offset store in UEFI, so the clock is not read as 1970
# (docs/uno-q-clock.md).
FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append:uno-q = " file://0001-arm64-dts-qcom-qrb2210-arduino-imola-keep-the-RTC-offset-in-UEFI.patch"
