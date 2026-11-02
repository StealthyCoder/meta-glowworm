# SPDX-License-Identifier: MIT

SUMMARY = "Ghostty terminfo entry"
DESCRIPTION = "The xterm-ghostty terminfo entry, so ncurses programs such as htop \
start in a session opened from the Ghostty terminal."
HOMEPAGE = "https://ghostty.org"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "ncurses-native"

SRC_URI = "file://xterm-ghostty.terminfo"

S = "${UNPACKDIR}"
B = "${WORKDIR}/build"

inherit allarch

do_compile() {
    tic -x -o ${B}/terminfo ${UNPACKDIR}/xterm-ghostty.terminfo
}

do_install() {
    install -d ${D}${datadir}/terminfo/x
    install -m 0644 ${B}/terminfo/x/xterm-ghostty ${D}${datadir}/terminfo/x/xterm-ghostty
}

FILES:${PN} = "${datadir}/terminfo/x/xterm-ghostty"
