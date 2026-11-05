# SPDX-License-Identifier: MIT

# Keeps the PMIC RTC offset in the persistent UEFI variable store of the TrustZone app, so the clock is not
# read as 1970 (docs/uno-q-clock.md).
FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append:uno-q = " \
    file://0001-firmware-qcom-scm-allow-qseecom-on-the-Arduino-UNO-Q.patch \
    file://0002-firmware-qcom-uefisecapp-hand-over-from-the-generic-efivars-operations.patch \
    file://0003-arm64-dts-qcom-qrb2210-arduino-imola-keep-the-RTC-offset-in-UEFI.patch \
"
