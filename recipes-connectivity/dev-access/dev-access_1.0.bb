# SPDX-License-Identifier: MIT

SUMMARY = "Development access: Wi-Fi profile, regulatory domain and root SSH key"
DESCRIPTION = "Installs a NetworkManager Wi-Fi profile and an authorized SSH key \
for root so a bench device can be reached over the network without a console. \
All inputs are supplied from outside the layer (see local.yml) and nothing is \
installed unless they are set. The resulting image carries the Wi-Fi passphrase \
in its rootfs: do not publish or upload it."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

# Absolute paths to local files, e.g. in local.yml:
#   DEV_ACCESS_WIFI_KEYFILE = "/home/me/.config/x/Net.nmconnection"
#   DEV_ACCESS_SSH_PUBKEY = "/home/me/.ssh/id_ed25519.pub"
DEV_ACCESS_WIFI_KEYFILE ?= ""
DEV_ACCESS_SSH_PUBKEY ?= ""
# 5 GHz channels are unusable under the default world regulatory domain.
DEV_ACCESS_REGDOM ?= ""

SRC_URI = "\
    ${@'file://' + d.getVar('DEV_ACCESS_WIFI_KEYFILE') if d.getVar('DEV_ACCESS_WIFI_KEYFILE') else ''} \
    ${@'file://' + d.getVar('DEV_ACCESS_SSH_PUBKEY') if d.getVar('DEV_ACCESS_SSH_PUBKEY') else ''} \
"

S = "${UNPACKDIR}"

do_install() {
    if [ -n "${DEV_ACCESS_WIFI_KEYFILE}" ]; then
        # NetworkManager ignores keyfiles that are not 0600 root-owned.
        install -d -m 0755 ${D}${sysconfdir}/NetworkManager/system-connections
        # The file fetcher unpacks absolute paths with their directory structure.
        install -m 0600 ${UNPACKDIR}${DEV_ACCESS_WIFI_KEYFILE} \
            ${D}${sysconfdir}/NetworkManager/system-connections/dev-access.nmconnection

        # ath10k_snoc finds no MAC address in the board data ("invalid MAC
        # address; choosing random") and so changes it on every boot, which
        # also changes the DHCP lease. A stable per-connection address fixes it.
        install -d -m 0755 ${D}${sysconfdir}/NetworkManager/conf.d
        cat > ${D}${sysconfdir}/NetworkManager/conf.d/10-dev-access-mac.conf <<EOF
[connection]
wifi.cloned-mac-address=stable
EOF
    fi

    if [ -n "${DEV_ACCESS_REGDOM}" ]; then
        install -d ${D}${sysconfdir}/modprobe.d
        echo "options cfg80211 ieee80211_regdom=${DEV_ACCESS_REGDOM}" \
            > ${D}${sysconfdir}/modprobe.d/dev-access-cfg80211.conf
    fi

    if [ -n "${DEV_ACCESS_SSH_PUBKEY}" ]; then
        # root's home is under /home, which OSTree does not preserve, so keep
        # the key in /etc. sshd takes the first value it sees and the stock
        # sshd_config includes sshd_config.d/ before its own AuthorizedKeysFile.
        install -d ${D}${sysconfdir}/ssh/sshd_config.d
        cat > ${D}${sysconfdir}/ssh/sshd_config.d/10-dev-access.conf <<EOF
AuthorizedKeysFile /etc/ssh/authorized_keys.%u .ssh/authorized_keys
# The image enables empty-password root login for the serial console; keys are the only way in over SSH.
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
EOF
        install -m 0644 ${UNPACKDIR}${DEV_ACCESS_SSH_PUBKEY} \
            ${D}${sysconfdir}/ssh/authorized_keys.root
    fi
}

FILES:${PN} = "${sysconfdir}"

RDEPENDS:${PN} = "networkmanager openssh-sshd"
