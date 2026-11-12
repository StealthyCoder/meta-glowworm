# SPDX-License-Identifier: MIT

SUMMARY = "Boot-time clock handling for the Arduino UNO Q: the network services wait for NTP"
DESCRIPTION = "The RTC in the PM4125 PMIC has no time set and cannot be set, so \
it reads 1970. The kernel must not copy it over the clock: meta-qcom-arduino \
builds the UNO Q kernel without CONFIG_RTC_HCTOSYS, which leaves the timestamp \
that systemd-timesyncd restored in place until NTP corrects it. (This recipe \
used to blacklist the rtc_pm8xxx module for the same effect, on kernels that \
still had CONFIG_RTC_HCTOSYS.) The services that talk to a server \
(aktualizr-lite, fioconfig, tailscaled) start after NTP has synced, or after \
two minutes without it. systemd-timesyncd retries after 5 s instead of 30 s, \
because its first attempt is made before the Wi-Fi is up."
HOMEPAGE = "https://github.com/StealthyCoder/meta-glowworm/blob/main/docs/uno-q-clock.md"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "uno-q"
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "\
    file://time-wait-sync-timeout.conf \
    file://time-sync-gate.conf \
    file://timesyncd-retry.conf \
"

S = "${UNPACKDIR}"

do_install() {
    # time-sync.target is only held back when systemd-time-wait-sync is in the
    # transaction, and the unit waits without end unless it has a timeout.
    install -d ${D}${systemd_system_unitdir}/systemd-time-wait-sync.service.d
    install -m 0644 ${UNPACKDIR}/time-wait-sync-timeout.conf \
        ${D}${systemd_system_unitdir}/systemd-time-wait-sync.service.d/10-uno-q.conf

    install -d ${D}${nonarch_libdir}/systemd/timesyncd.conf.d
    install -m 0644 ${UNPACKDIR}/timesyncd-retry.conf \
        ${D}${nonarch_libdir}/systemd/timesyncd.conf.d/10-uno-q.conf

    for unit in aktualizr-lite fioconfig tailscaled; do
        install -d ${D}${systemd_system_unitdir}/${unit}.service.d
        install -m 0644 ${UNPACKDIR}/time-sync-gate.conf \
            ${D}${systemd_system_unitdir}/${unit}.service.d/10-uno-q-time-sync.conf
    done
}

FILES:${PN} += "\
    ${nonarch_libdir}/systemd/timesyncd.conf.d \
    ${systemd_system_unitdir}/systemd-time-wait-sync.service.d \
    ${systemd_system_unitdir}/aktualizr-lite.service.d \
    ${systemd_system_unitdir}/fioconfig.service.d \
    ${systemd_system_unitdir}/tailscaled.service.d \
"
