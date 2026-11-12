# glowworm-mcu reads and flashes the UNO Q's MCU sketch with OpenOCD's linuxgpiod driver, which is built on libgpiod
# 1.x and so speaks only version 1 of the GPIO character-device ABI. linux-arduino 7.2 stopped enabling
# CONFIG_GPIO_CDEV_V1 (the Kconfig option lost its "default y", and no defconfig sets it), so on 7.2.11 OpenOCD fails
# with "Error get line swdio" and the MCU supervisor never starts the sketch: the LED matrix stays on the loader's
# boot animation. This fragment turns the option back on. Delete it once the MCU image carries an OpenOCD that
# speaks the v2 ABI.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:uno-q = " file://gpio-cdev-v1.cfg"
