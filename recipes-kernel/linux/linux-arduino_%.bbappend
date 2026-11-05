# SPDX-License-Identifier: MIT

# Lets the host write the PMIC RTC, so the clock is not read as 1970
# (docs/uno-q-clock.md).
FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append:uno-q = " file://0001-arm64-dts-qcom-qrb2210-arduino-imola-let-the-host-set-the-RTC.patch"
