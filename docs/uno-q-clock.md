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

`uno-q-clock` installs `/usr/lib/modprobe.d/uno-q-rtc.conf` with `blacklist rtc_pm8xxx`. udev finds
the driver through a device tree alias, which a blacklist entry stops. No RTC registers, so
`hctosys` has nothing to apply and the timestamp that `timesyncd` restored at 9.9 s stays.

Check on the board:

```sh
timedatectl | grep -E 'RTC time|synchronized'   # RTC time: n/a
lsmod | grep rtc_pm8xxx                         # no output
journalctl -b | grep -c 'setting system clock'  # 0
```

This does not make the clock exact. After a boot it is as old as the last NTP sync or clean shutdown
(minutes, normally), and it is stepped once NTP is reached.

## Starting the network services after NTP

`aktualizr-lite`, `fioconfig` and `tailscaled` have a drop-in (`10-uno-q-time-sync.conf`) with
`Wants=systemd-time-wait-sync.service time-sync.target` and `After=time-sync.target`. They talk to a
server, so a clock that is minutes off is no use to them, and they retry on their own anyway.

- `systemd-time-wait-sync.service` is disabled on the image and ships with `TimeoutStartSec=infinity`.
  The `Wants=` puts it in their start transaction, which is what holds `time-sync.target` back, and a
  drop-in (`10-uno-q.conf`) limits the wait to two minutes. Without NTP (no Wi-Fi, a network that
  blocks UDP 123) the three services start two minutes after the unit begins, and
  `systemd-time-wait-sync.service` shows as failed.
- `docker`, `containerd` and the apps are not held back: they must come up without a network. With the
  blacklist their clock is already close to right.
- Expect the services to start roughly as late as the first NTP sync, about 12 seconds after
  NetworkManager on the measured boot. NetworkManager itself starts 87 s into the boot, a delay that
  is not looked at here.

## The proper fix

The firmware already provides what the driver needs. The board's UEFI has the variable
`RTCInfo-882f8c2b-9646-435f-8de5-f208ff80c1bd` (16 bytes: 4 bytes of attributes, `NV|BS|RT`, and 12 bytes
of zeros), the exact variable that `qcom,uefi-rtc-info` names, and the kernel has `CONFIG_EFIVAR_FS`
and the EFI runtime services. Adding `qcom,uefi-rtc-info;` to `rtc@6000` lets the driver store an
offset in that variable, so the RTC keeps the time across reboots while the board is powered.

Not verified:

- That `SetVariable` works at runtime on this firmware (the variable is writable by its attributes, a
  write was not tried).
- Whether the PMIC allows the host to write its RTC registers (`allow-set-time`). Nothing in the
  Arduino documents says.
- `nvmem-cells` has no candidate: `pm4125.dtsi` defines no SDAM node.

Hardware: the RTC runs from the PMIC supply and stops when all power is lost. The `VCOIN` pin (JMISC
pin 59) feeds only the PMIC's RTC ("does not power the Linux or MCU domains", UNO Q datasheet,
power supply section); a coin cell there would keep it running without the 5 V supply. No cell is fitted.

## Upstream

The fix belongs in the board's device tree, in `meta-qcom-arduino`'s kernel (`linux-arduino`) or in
`pm4125.dtsi`. It does not belong in `meta-foundries`, a generic layer for many machines, where
blacklisting a PMIC RTC driver would also switch off the RTC of boards that have a working one. The
blacklist here is a workaround for an image that cannot change the kernel.
