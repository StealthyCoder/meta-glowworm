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
| 86.7 s | NetworkManager starts (late because `uno-q-memhole.service` held back `sysinit.target`, see [Boot time](#boot-time)). |
| 86.9 to 96.3 s | `aktualizr-lite`, `tailscaled`, `containerd` and `docker` start, all in 1970. |
| 99.2 s | The first NTP sync (`Initial clock synchronization`) sets the real time. |

The RTC is the one in the PM4125 PMIC (`rtc@6000`). It has never been set and cannot be: in
`drivers/rtc/rtc-pm8xxx.c` `set_time` writes the RTC only with `allow-set-time`, and otherwise needs an
offset store (an `nvmem-cells` cell named `offset`, or `qcom,uefi-rtc-info`) and returns `-ENODEV`
without one. The `rtc@6000` node in `pm4125.dtsi` has none of the three, so `CONFIG_RTC_SYSTOHC` never
updates it either. The RTC just counts seconds from zero (1.2 million, about 14 days, on 2026-11-05;
presumably since the PMIC last lost power) and `hctosys` takes that for the date.

## What this layer does

The kernel does not copy the RTC over the clock any more: `meta-qcom-arduino` builds the UNO Q kernel
with `# CONFIG_RTC_HCTOSYS is not set` (see [Upstream](#upstream)), so the timestamp that `timesyncd`
restored at about 10 s stays. This layer used to keep the driver out instead, with a
`blacklist rtc_pm8xxx` entry in `/usr/lib/modprobe.d/uno-q-rtc.conf` (updates 26 to 35, for kernels that
still had `CONFIG_RTC_HCTOSYS`). That file is gone, the RTC driver loads and `/dev/rtc0` exists.

Check on the board:

```sh
zcat /proc/config.gz | grep HCTOSYS             # # CONFIG_RTC_HCTOSYS is not set
ls /dev/rtc0                                    # exists: the driver is loaded
journalctl -b | grep -c 'setting system clock'  # 0
```

`timedatectl` shows an `RTC time` in 1970 (the RTC is never set); nothing uses it. If the kernel
provider ever changes (for example to `linux-qcom-next`), check `CONFIG_RTC_HCTOSYS` first: with it on,
the 1970 clock comes back.

Seen on the board with the blacklist (updates 26 and 28): `timesyncd` restores the clock at 10 s, nothing
sets it back, the first NTP sync is at about 100 s, the journal has no 1970 lines, and the apps show
`Up N minutes`.

Seen on the board without it (update 35, kernel 7.2.11, `rtc-pm8xxx` loaded): `timesyncd` restores the
clock at about 10 s and `rtc0` registers at 14.1 s with no `setting system clock` line. Nothing sets the
clock back, the journal has no 1970 entries (the few before the restore carry an earlier 2026 date, 43
minutes before the boot in the run measured), and the first NTP sync is at about 46 s.

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
  hctosys switched off their clock is already close to right.
- Expect the services to start as late as the first NTP sync, which depends on how fast the Wi-Fi
  comes up and on the `timesyncd` retry: at about 37 s on the measured boot, see [Boot time](#boot-time).

## Boot time

NetworkManager used to start 87 s into the boot, which is why the network services only started at
about 100 s. It was not the network: `uno-q-memhole.service` (`uno-q-memhole` recipe) takes the unusable
RAM pages out of service, is ordered `Before=sysinit.target`, and its script forked `dd`, `od` and `tr`
for each of the 10,751 pages of the window to read the page flags. That is 7 ms a page, 77 s in all, and
D-Bus, NetworkManager, containerd and Docker are all ordered after `sysinit.target`. The script now reads
the flags of the whole window in one pass and takes 3.4 s with the same result (10,751 pages offlined).

Measured with `journalctl -b -o short-monotonic`, before the change (2026-11-05) and on update 33
(2026-11-06):

| Uptime | Before | Update 33 | Update 33, 5 s retry |
| --- | --- | --- | --- |
| `uno-q-memhole.service` finished | 85.8 s (started at 8.5 s) | 11.9 s (started at 8.5 s) | 12.3 s |
| NetworkManager starts | 86.8 s | 14.6 s | 14.7 s |
| Docker started | 94 s | 22.2 s | 21.5 s |
| Wi-Fi connection active | not measured | 27.9 s | 28.0 s |
| First NTP sync | 99.2 s | 58.4 s | 36.9 s |
| `aktualizr-lite`, `fioconfig`, `tailscaled` | about 100 s | 58.6 to 58.8 s | 37.2 to 37.3 s |

The last column is update 33 with `ConnectionRetrySec=5s` (see below) put in
`/etc/systemd/timesyncd.conf.d/` on the board, measured on 2026-11-06.

Update 34 ships the setting in the image. With nothing in `/etc`, the board syncs at 31.5 s (the Wi-Fi
connection is active at 27.2 s) and `aktualizr-lite`, `fioconfig` and `tailscaled` start at 31.8 to 32.0 s.
There are no wrong dates, no failed units, and all apps show `Up N minutes`.

What is left on update 33, in order:

- `wlan0` appears at 20.2 s, once the `ath10k` firmware is loaded (20.0 s), and NetworkManager is ready
  for it at 21.9 s. It auto-activates the connection only at 26.8 s and logs nothing in between (probably
  its initial scan; not checked). The association then takes 0.4 s, and the connection is active at 27.9 s.
- The Wi-Fi is up at 27.9 s, and the first NTP answer only comes at 58.4 s, 30.5 s later. That is
  `systemd-timesyncd` backing off, found with `SYSTEMD_LOG_LEVEL=debug` on a second boot:
  - It makes its first attempt at 21.7 s, when it already sees a network. That is not the Wi-Fi, which
    is active at 28.0 s (probably the Docker bridges; not checked). `systemd-resolved` has no DNS server yet, so all lookups fail at once (`io.systemd.Resolve.MaxAttemptsReached`,
    13 ms each, four servers) and `timesyncd` starts its retry timer.
  - It then ignores the network changes that follow, among them the Wi-Fi coming up (`Delaying attempts to
    contact servers.` at 28.0, 30.8 and 31.4 s) and tries again when the timer fires.
  - The retry interval is `ConnectionRetrySec=`, 30 s by default. This layer sets it to 5 s
    (`/usr/lib/systemd/timesyncd.conf.d/10-uno-q.conf`), and the first sync moved from 58.4 s to 36.9 s
    (last column above). It is still not right at the Wi-Fi's 28.0 s: the timer fired at 27.1 s without
    an attempt (`Delaying attempts to contact servers.`) and the next one came at 36.7 s.
  - The 58.4 s boot was not logged at debug level; it shows the same gap of one retry interval.

A board that still has the hand-installed `/etc/systemd/system/uno-q-memhole.service` and
`/etc/uno-q-memhole.sh` runs the old script: a unit in `/etc` shadows the one in `/usr/lib`. Point the link
`/etc/systemd/system/sysinit.target.wants/uno-q-memhole.service` at
`/usr/lib/systemd/system/uno-q-memhole.service`, remove the two files, run `systemctl daemon-reload`,
and check `systemctl cat uno-q-memhole.service` before the next boot.

## Giving the RTC an offset store (tried, not enough)

The driver can keep an offset in the UEFI variable `RTCInfo-882f8c2b-9646-435f-8de5-f208ff80c1bd`
(`qcom,uefi-rtc-info` on `rtc@6000`), and the board's UEFI already has that variable (16 bytes: `NV|BS|RT`
attributes and 12 bytes of zeros). Tried on 2026-11-05 with a `linux-arduino` patch that sets the
property on the Arduino board only (branch `try-rtc-uefi-offset`, update 27 on the board):

- Within one boot it works. About 7 minutes after the first NTP sync the driver had written the offset
  into `RTCInfo` (`07 00 00 00 1a d5 04 58 ...`) and `rtc0` read the right time.
- It does not survive a reset. On the next boot the driver read the offset as zero and `hctosys` set the
  clock to `1980-01-20T03:36:09` at 13.6 s, as on the first boot, so the stale date only moved from 1970
  to 1980.

The cause is the firmware. It has an `RTStorageVolatile-b2ac5fc9-92b7-4acd-aeac-11e818c3130c`
variable that contains `VolatileVars.bin`: variables written from Linux through the normal EFI runtime
services stay in RAM, whatever their `NV` attribute says, and the write still returns success. The
Qualcomm laptops persist them through a TrustZone app (`qcom.tz.uefisecapp`, the kernel's
`qcom_qseecom_uefisecapp` driver). This kernel has that driver (`CONFIG_QCOM_QSEECOM_UEFISECAPP=y`) and
the board's TrustZone has the service, but it is not used:

```
qcom_scm firmware:scm: qseecom: found qseecom with version 0x1402000
qcom_scm firmware:scm: qseecom: untested machine, skipping
```

`arduino,imola` is not in `qcom_scm_qseecom_allowlist` (`drivers/firmware/qcom/qcom_scm.c`; "we do not yet
support re-entrant calls via the qseecom interface"). The driver's `efivars_register()` also returns
`-EBUSY` while the generic EFI variable operations are registered, and they are here, because this
firmware reports the variable services as supported (the laptops' firmware does not).

### The TrustZone app, tried: it does not persist either

Tried on 2026-11-06 (branch `try-rtc-trustzone`, update 31 on the board) with two kernel patches: the
allowlist entry, and `efivars_generic_ops_unregister()` before the app's `efivars_register()`, as
`tee_stmm_efi.c` does for OP-TEE. The handoff works and nothing hangs:

```
qcom_qseecom qcom_qseecom: setting up client for qcom.tz.uefisecapp
efivars: Unregistered efivars operations
efivars: Registered efivars operations
```

`efivarfs` lists the variables, the RTC driver probes, and after NTP the offset is written to `RTCInfo` and
read back. But a reboot loses it, as before: the second boot set the clock to `1980-01-20` at 13.5 s.
`bootctl` shows the same from systemd's side. It writes `LoaderSystemToken` once, and on the second boot it
logged `Successfully initialized system token in EFI variable` again, because the variable was gone.
So the app keeps runtime writes in the secure world's RAM. Nothing reaches the `uefivarstore` partition
(encrypted; Linux reads it and has not written to it). Persisting there presumably needs the
re-entrant calls into the normal world (a listener) that the allowlist comment says are not supported.
With this the EFI variable routes are exhausted on this board.

## Letting the host write the RTC (tried, refused by the hardware)

Tried on 2026-11-05 with `allow-set-time;` on `rtc@6000` for the Arduino board (branch
`try-rtc-allow-set-time`, update 29 on the board). The driver then writes the PMIC registers directly
instead of keeping an offset. It does not work: the PMIC arbiter refuses every write.

```
spmi spmi-0: disallowed SPMI write to sid=0, addr=0x6046
```

`spmi-pmic-arb` returns `-EPERM` for a peripheral whose write owner (`write_ee`) is not Linux's execution
environment. The firmware gave the RTC to another owner, so the host can read the counter and never set
it. `hctosys` reads the raw counter (`1970-01-15`), `rtc0` stays there, `CONFIG_RTC_SYSTOHC` retries
every few seconds and the kernel log fills with the refusal (1820 lines in five minutes). This fits the
offset in UEFI that Qualcomm's own platforms use instead of setting the RTC. Do not set `allow-set-time`
on this board.

Not tried: `nvmem-cells`, since `pm4125.dtsi` defines no SDAM node to hold the offset.

## Hardware

The RTC runs from the PMIC supply and stops when all power is lost. The `VCOIN` pin (JMISC pin 59) feeds
only the PMIC's RTC ("does not power the Linux or MCU domains", UNO Q datasheet, power supply section); a
coin cell there would keep it running without the 5 V supply. No cell is fitted.

## Upstream

### hctosys switched off in the kernel (meta-qcom-arduino 4697cfa)

On 2026-11-11 `meta-qcom-arduino` merged [PR #17](https://github.com/qualcomm-linux/meta-qcom-arduino/pull/17):
the UNO Q and VENTUNO Q kernels are built with `# CONFIG_RTC_HCTOSYS is not set` ("no battery"). The
kernel then no longer replaces the clock that `systemd-timesyncd` restored with the RTC's 1970 date, the
same effect as the old blacklist, with the RTC driver left loaded. This layer pins that commit ahead of
`meta-foundries` (see the README). It was proven on the board on 2026-11-12: `/proc/config.gz` has the
option off, and a boot with the blacklist masked showed `setting system clock` at 0, no 1970 entries and
a sane clock. The blacklist is therefore removed.

### What still needs the firmware

No kernel patch can fix this on the current firmware: Linux cannot set the RTC (the arbiter refuses the
write) and no EFI variable survives a reset. It needs a change in the firmware, either write ownership of
the RTC for Linux (then `allow-set-time` on the Arduino board, and a coin cell on `VCOIN` for power cuts)
or a persistent store for runtime variables. That is a question for Arduino and Qualcomm; the board's
kernel is `arduino/linux-qcom` (`linux-arduino` in `meta-qcom-arduino`).

The old blacklist did not belong in `meta-foundries` or `meta-qcom`, generic layers for many machines,
where blacklisting a PMIC RTC driver would also switch off the RTC of boards that have a working one. It
was a workaround for this board, and the kernel option has replaced it.
