# SPDX-License-Identifier: MIT

SUMMARY = "Keeps the unset PMIC RTC of the Arduino UNO Q from resetting the clock to 1970"
DESCRIPTION = "The RTC in the PM4125 PMIC has no time set and cannot be set: \
the device tree gives the rtc-pm8xxx driver neither allow-set-time nor an \
offset store. The driver loads late as a module, and CONFIG_RTC_HCTOSYS then \
steps the system clock back to 1970-01-14, over the timestamp that \
systemd-timesyncd restored seconds earlier. Not loading the driver leaves \
that timestamp in place until NTP corrects it."
HOMEPAGE = "https://github.com/StealthyCoder/meta-glowworm/blob/main/docs/uno-q-clock.md"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "uno-q"
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "file://uno-q-rtc.conf"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${nonarch_base_libdir}/modprobe.d
    install -m 0644 ${UNPACKDIR}/uno-q-rtc.conf ${D}${nonarch_base_libdir}/modprobe.d/uno-q-rtc.conf
}

FILES:${PN} += "${nonarch_base_libdir}/modprobe.d/uno-q-rtc.conf"
