# openocd-glowworm

Builds an OpenOCD with the `linuxgpiod` driver on **libgpiod 2.x**, for the `glowworm-mcu` container of the Arduino UNO Q, and
packages it as a `.deb` that Glowworm's `unpack_arm64` can read.

This is not a Yocto recipe and nothing in the OS image uses it: the binary goes into a container with a Debian base, so it is
built with Docker, on arm64, outside BitBake. It lives in `contrib/` (the place OpenEmbedded layers keep tools that are not
recipes) so that the pinned binary can be rebuilt from this repository. The built `.deb` is a release asset of this repository.

## Why this exists

`glowworm-mcu` reads (and, when the sketch differs, flashes) the STM32U585's sketch over SWD, which the QRB2210 bit-bangs on two
GPIO lines (25 and 26 of `gpiochip1`). That goes through OpenOCD's `linuxgpiod` driver, and the supervisor does it on every start.

- Debian bookworm's OpenOCD 0.12.0 uses libgpiod **1.6.3**, which talks the v1 GPIO character-device ABI.
- `linux-arduino` 7.2 no longer enables `CONFIG_GPIO_CDEV_V1` (the Kconfig option lost its `default y`), so on 7.2.11 that OpenOCD
  fails with `Error get line swdio` and the supervisor restarts forever. The kernel fragment in `recipes-kernel/linux/` is the
  stop-gap.
- Debian trixie does not help: its OpenOCD 0.12.0 is built without the `linuxgpiod` driver.
- Upstream OpenOCD **master** has had libgpiod v2 support since 2025-09-27 (`c92cc6b5` and siblings), but there is no release with
  it (the last is v0.12.0, 2023). So this builds a pinned master commit.

## What it builds

`openocd-glowworm_0.12.0+git<date>.<sha>-1_arm64.deb` with `./usr/bin/openocd`, `./usr/share/openocd/scripts/` and
`./usr/lib/aarch64-linux-gnu/` (`libgpiod.so.3` and `libjim.so.0.81`, the two libraries the base image lacks): the paths the
supervisor uses. The build runs in `debian:bookworm-slim`, pinned by the **same digest as Glowworm's `container/mcu/Dockerfile`**,
so the binary links the image's glibc (2.36). libgpiod 2.1.3 comes from bookworm-backports. `package.sh` fails the build unless:

1. `adapter driver linuxgpiod` is accepted,
2. the binary links `libgpiod.so.3` (v2) and not `libgpiod.so.2` (v1),
3. it needs no glibc symbol newer than 2.36,
4. the deb has the `data.tar.xz` member Glowworm reads.

## Status

| | |
| --- | --- |
| Built | 2026-11-12 on a `t2a-standard-4` in `europe-west4-a` from the `debian-12-arm64` family: about 5 minutes from `gcp-build.sh` to a deleted VM |
| Released | tag `openocd-glowworm-4900bcdf-1`, OpenOCD `4900bcdf`, sha256 `a12aab304840b283e36f9ed52269a039e36d37008511a4199e849bf5b53ca910` |
| Running | in Glowworm's update 38 on a UNO Q: the supervisor's SWD dump works (`the MCU already holds this sketch`, container healthy, 0 restarts) |
| Not yet shown | that it works **without** `CONFIG_GPIO_CDEV_V1`: that UNO Q's kernel still has it on. See "Proving it" |

## Running it (it needs an arm64 machine)

The laptop that builds Glowworm cannot run arm64 binaries, so the build happens elsewhere. Pick one. Run these from this directory.

**A throwaway GCP VM** (a few minutes, cents):

```sh
./gcp-build.sh --project YOUR_PROJECT            # creates a t2a VM, builds, copies out/ back, deletes the VM
./gcp-build.sh --project YOUR_PROJECT --dry-run  # only prints the gcloud commands
./gcp-build.sh --project YOUR_PROJECT --cleanup  # deletes a VM that a failed run left behind
```

`--project` is mandatory on purpose: the script never uses gcloud's default project (on a work laptop that can be a production
one). Nothing private goes to the VM, only this directory, and the VM deletes itself after 2 hours (`--max-run-duration`) even if
the script dies. If `create` complains about the zone or the image, change `--zone` or the image family in the script.

**The UNO Q itself** (free, but it shares its RAM and disk with the running apps: check `free -m` and `df -h /var/lib/docker`
first, and keep `--jobs` low): copy this directory over and run `./build.sh --jobs 2` there. It has Docker.

**Any other arm64 box**, or an x86 one with `qemu-user-static` and binfmt: `./build.sh`.

`OPENOCD_PLATFORM=linux/amd64 ./build.sh` makes a test deb on x86. It proves the recipe compiles and the checks pass; it is not for
the board.

## Publishing and using the result

1. Make a release of this repository with the deb and `SHA256SUMS` as assets. Glowworm downloads the URL without credentials and
   checks the sha256 (`file://` is not supported), so the repository must be public:

   ```sh
   gh release create openocd-glowworm-<sha8>-<n> out/openocd-glowworm_*_arm64.deb out/SHA256SUMS \
       -R StealthyCoder/meta-glowworm --target main --title "openocd-glowworm <version> (arm64)" --notes-file notes.md
   ```

   The notes say which OpenOCD commit it is, how it was built, and the licenses (OpenOCD GPL-2.0-or-later, libgpiod
   LGPL-2.1-or-later, Jim Tcl BSD-2-Clause).
2. In Glowworm's `container/mcu/app.toml`, the one OpenOCD line of `unpack_arm64` is
   `"mcu.tar:opt/glowworm/mcu/openocd <URL>/<deb> sha256:<sum>"` (`build.sh` prints it); `mode_arm64` stays. The URL has `%2B`
   where the file name has a `+`.
3. `glowworm ship` builds the app and plans the update.

## Proving it

The point is that OpenOCD works **without** the v1 ABI. That can only be shown on a kernel without `CONFIG_GPIO_CDEV_V1`:

1. Delete `recipes-kernel/linux/linux-arduino_%.bbappend` and `recipes-kernel/linux/files/gpio-cdev-v1.cfg`, build the OS, OTA it.
2. On the board, `zcat /proc/config.gz | grep CDEV_V1` must say `# CONFIG_GPIO_CDEV_V1 is not set`.
3. After the reboot the `glowworm-mcu` container must stay up with 0 restarts, its log must say `the sketch answers; the matrix is
   ready` with no `Error get line swdio`, and the LED matrix must go black.

If it does not, put the fragment back: the OS is fine with it.

## Bumping OpenOCD

Change `OPENOCD_COMMIT` in the `Dockerfile` (a full 40-character sha), rebuild, publish a new release and re-pin its URL and sha256
in Glowworm's `app.toml`. The commit in the `Dockerfile` and in the deb's description is the source of the binary.
