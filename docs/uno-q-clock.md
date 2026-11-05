# The UNO Q clock at boot

After every boot the UNO Q's clock reads 1970 for about 90 seconds, until the first NTP sync. In that
time `aktualizr-lite`, `fioconfig`, `tailscaled`, `containerd` and `docker` start, so their logs say
`Jan 14 1970`, the apps show `Up 56 years`, and `aktualizr-lite` logs `curl error 60` (certificate not
yet valid).

## Cause

The clock is correct early in the boot and then goes backwards. Measured on the board (kernel 7.0.14,
`journalctl -b -o short-monotonic`):

| Uptime | What happens |
| --- | --- |
| 9.9 s | `systemd-timesyncd` advances the clock to its recorded timestamp, the mtime of `/var/lib/systemd/timesync/clock`. This is correct to within the time since the last sync. |
| 13.9 s | The `rtc-pm8xxx` module loads and `CONFIG_RTC_HCTOSYS` sets the clock to `1970-01-14T23:33:16`. |
| 86.7 s | NetworkManager starts. |
| 86.9 to 96.3 s | `aktualizr-lite`, `tailscaled`, `containerd` and `docker` start, all in 1970. |
| 99.2 s | The first NTP sync (`Initial clock synchronization`) sets the real time. |

The RTC is the one in the PM4125 PMIC (`rtc@6000`). It has never been set and cannot be: in
`drivers/rtc/rtc-pm8xxx.c` `set_time` writes the RTC only with `allow-set-time`, and otherwise needs an
offset store (an `nvmem-cells` cell named `offset`, or `qcom,uefi-rtc-info`) and returns `-ENODEV`
without one. The `rtc@6000` node in `pm4125.dtsi` has none of the three, so `CONFIG_RTC_SYSTOHC` never
updates it either. The RTC just counts seconds from zero (1.2 million, about 14 days, on 2026-11-05;
presumably since the PMIC last lost power) and `hctosys` takes that for the date.

## What this layer does

### Give the RTC an offset store

The firmware already provides one. The board's UEFI has the variable
`RTCInfo-882f8c2b-9646-435f-8de5-f208ff80c1bd` (16 bytes: 4 bytes of attributes, `NV|BS|RT`, and 12 bytes
of zeros), the variable that `qcom,uefi-rtc-info` names, and the kernel has `CONFIG_EFIVAR_FS` and the
EFI runtime services.

`recipes-kernel/linux/linux-arduino_%.bbappend` adds a patch to `linux-arduino` that gives `rtc@6000` a
label and sets `qcom,uefi-rtc-info` on the Arduino board (`qrb2210-arduino-imola-base.dts`). The
property is not set in `pm4125.dtsi`, which the Qualcomm RB1 shares.

Expected behaviour, not yet seen on a board:

- The first boot of an image with the patch still reads a wrong date (the empty variable means offset
  zero from the GPS epoch, so about 1980-01-20), until the first NTP sync.
- The kernel then writes the RTC about every 11 minutes while NTP is synced. With the offset store, that
  write updates the UEFI variable.
- From the next boot, the RTC reads the right time when the driver loads at about 14 s.

Check on the board:

```sh
journalctl -b | grep 'setting system clock'   # the real date from the second boot on
cat /sys/class/rtc/rtc0/date                   # today
od -An -tx1 /sys/firmware/efi/efivars/RTCInfo-882f8c2b-9646-435f-8de5-f208ff80c1bd   # no longer all zeros
```

Not verified: that `SetVariable` works at runtime on this firmware, and what the firmware does with the
variable. The Qualcomm laptops use the same variable.

### Start the network services after NTP

`aktualizr-lite`, `fioconfig` and `tailscaled` have a drop-in (`10-uno-q-time-sync.conf`) with
`Wants=systemd-time-wait-sync.service time-sync.target` and `After=time-sync.target`. They talk to a
server, so a clock that is minutes off is no use to them, and they retry on their own anyway.

- `systemd-time-wait-sync.service` is disabled on the image and ships with `TimeoutStartSec=infinity`.
  The `Wants=` puts it in their start transaction, which is what holds `time-sync.target` back, and a
  drop-in (`10-uno-q.conf`) limits the wait to two minutes. Without NTP (no Wi-Fi, a network that
  blocks UDP 123) the three services start two minutes after the unit begins, and
  `systemd-time-wait-sync.service` shows as failed.
- `docker`, `containerd` and the apps are not held back: they must come up without a network. With the
  RTC set their clock is already close to right.
- Expect the services to start roughly as late as the first NTP sync, about 12 seconds after
  NetworkManager on the measured boot. NetworkManager itself starts 87 s into the boot, a delay that
  is not looked at here.

### The fallback

If the firmware refuses the variable, `blacklist rtc_pm8xxx` in `/usr/lib/modprobe.d` keeps the
driver from loading, so `timesyncd`'s restored timestamp stays. It was the first version of this layer's
fix (commit `488b7ac`, branch `bump-meta-foundries-79cb34b`).

## Hardware

The RTC runs from the PMIC supply and stops when all power is lost, which resets its count (the offset
in UEFI then makes the clock stale but never 1970). The `VCOIN` pin (JMISC pin 59) feeds only the
PMIC's RTC ("does not power the Linux or MCU domains", UNO Q datasheet, power supply section); a coin
cell there would keep it running without the 5 V supply. No cell is fitted. Nothing in the Arduino
documents says whether the host may write the RTC registers (`allow-set-time`); `nvmem-cells` has no
candidate, because `pm4125.dtsi` defines no SDAM node.

## Upstream

The patch belongs in the board's device tree, in `arduino/linux-qcom` (`pm4125.dtsi` label plus
`qrb2210-arduino-imola-base.dts`), where this layer's copy can then go. It does not belong in
`meta-foundries`, a generic layer for many machines.
