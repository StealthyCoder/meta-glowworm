# SPDX-License-Identifier: MIT

SUMMARY = "Keeps unusable RAM pages of the Arduino UNO Q out of the allocator"
DESCRIPTION = "The UNO Q memory map lists the physical window 0x7a000000-0x7c9fefff \
as RAM, and writes to it raise synchronous external aborts under memory load. \
A boot-time oneshot soft-offlines the free pages of that window."
HOMEPAGE = "https://github.com/qualcomm-linux/meta-qcom-arduino/issues/16"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "uno-q"
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "\
    file://uno-q-memhole.sh \
    file://uno-q-memhole.service \
"

S = "${UNPACKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "uno-q-memhole.service"

do_install() {
    install -d ${D}${libexecdir} ${D}${systemd_system_unitdir}
    install -m 0755 ${UNPACKDIR}/uno-q-memhole.sh ${D}${libexecdir}/uno-q-memhole
    install -m 0644 ${UNPACKDIR}/uno-q-memhole.service ${D}${systemd_system_unitdir}/uno-q-memhole.service
}
