# SPDX-License-Identifier: MIT

# VARIANT names the derivative; NAME and ID stay the distro's so tools that match on ID keep working.
OS_RELEASE_FIELDS:append:uno-q = " VARIANT VARIANT_ID"
VARIANT:uno-q = "Glowworm"
VARIANT_ID:uno-q = "glowworm"
PRETTY_NAME:uno-q = "Glowworm on ${DISTRO_NAME} ${VERSION}"
