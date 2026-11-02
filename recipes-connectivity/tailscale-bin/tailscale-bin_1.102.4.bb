# SPDX-License-Identifier: MIT

SUMMARY = "Tailscale from the official prebuilt binaries"
DESCRIPTION = "Installs Tailscale's published static aarch64 binaries together with \
their systemd unit. The tarball is pinned by sha256."
HOMEPAGE = "https://tailscale.com"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9"

COMPATIBLE_HOST = "aarch64.*-linux"

SRC_URI = "https://pkgs.tailscale.com/stable/tailscale_${PV}_arm64.tgz"
SRC_URI[sha256sum] = "9dd1e6a592a014bbaea0103167ffe299adeda4ba14e078ce9c2895364f6c4c3f"

S = "${UNPACKDIR}/tailscale_${PV}_arm64"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tailscaled.service"

# The upstream binaries are static and already stripped.
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "already-stripped ldflags"

do_install() {
    install -d ${D}${bindir} ${D}${sbindir} ${D}${systemd_system_unitdir} ${D}${sysconfdir}/default
    install -m 0755 ${S}/tailscale ${D}${bindir}/tailscale
    install -m 0755 ${S}/tailscaled ${D}${sbindir}/tailscaled
    install -m 0644 ${S}/systemd/tailscaled.service ${D}${systemd_system_unitdir}/tailscaled.service
    install -m 0644 ${S}/systemd/tailscaled.defaults ${D}${sysconfdir}/default/tailscaled
}

RDEPENDS:${PN} = "iptables"
RPROVIDES:${PN} = "tailscale tailscaled"
RCONFLICTS:${PN} = "tailscale tailscaled"
