# SPDX-License-Identifier: MIT

FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

# contrib/fioconfig-oneshot calls `mktemp -d` with a relative template and needs a writable working
# directory. fioconfig.service sets none, so systemd starts it in the read-only root and every remote
# one-shot action fails before it reports back to the server.
SRC_URI:append:uno-q = " file://working-directory.conf"

do_install:append:uno-q() {
    install -d ${D}${systemd_system_unitdir}/fioconfig.service.d
    install -m 0644 ${UNPACKDIR}/working-directory.conf ${D}${systemd_system_unitdir}/fioconfig.service.d/
}

FILES:${PN}:append:uno-q = " ${systemd_system_unitdir}/fioconfig.service.d/working-directory.conf"
