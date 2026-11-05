# SPDX-License-Identifier: MIT

SUMMARY = "Starts the network services of the Arduino UNO Q after the clock is set by NTP"
DESCRIPTION = "aktualizr-lite, fioconfig and tailscaled start after \
systemd-timesyncd has synced the clock, or after two minutes without it. \
The wait is a bounded systemd-time-wait-sync, which is disabled on the image \
and otherwise waits without end. See docs/uno-q-clock.md."
HOMEPAGE = "https://github.com/StealthyCoder/meta-glowworm/blob/main/docs/uno-q-clock.md"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "uno-q"
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "\
    file://time-wait-sync-timeout.conf \
    file://time-sync-gate.conf \
"

S = "${UNPACKDIR}"

do_install() {
    # time-sync.target is only held back when systemd-time-wait-sync is in the
    # transaction, and the unit waits without end unless it has a timeout.
    install -d ${D}${systemd_system_unitdir}/systemd-time-wait-sync.service.d
    install -m 0644 ${UNPACKDIR}/time-wait-sync-timeout.conf \
        ${D}${systemd_system_unitdir}/systemd-time-wait-sync.service.d/10-uno-q.conf

    for unit in aktualizr-lite fioconfig tailscaled; do
        install -d ${D}${systemd_system_unitdir}/${unit}.service.d
        install -m 0644 ${UNPACKDIR}/time-sync-gate.conf \
            ${D}${systemd_system_unitdir}/${unit}.service.d/10-uno-q-time-sync.conf
    done
}

FILES:${PN} += "\
    ${systemd_system_unitdir}/systemd-time-wait-sync.service.d \
    ${systemd_system_unitdir}/aktualizr-lite.service.d \
    ${systemd_system_unitdir}/fioconfig.service.d \
    ${systemd_system_unitdir}/tailscaled.service.d \
"
