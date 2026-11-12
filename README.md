# meta-glowworm

An OpenEmbedded / Yocto Project layer for the Arduino UNO Q. It adds GPU userspace (Vulkan on the
Adreno 702) and a few bench tools to the [meta-foundries](https://github.com/foundriesio/meta-foundries)
image of the UNO Q.

It belongs to Glowworm, an experiment in running AI inference on the UNO Q. Inference runtimes ship
as containers, so this layer carries only what the host OS has to provide.

## Getting in Contact

* [Report an Issue on GitHub](../../issues) — for bugs, build failures, and feature requests.
* To report a security vulnerability, follow the process in [SECURITY.md](SECURITY.md).

## Maintainer(s)

- Eric Bode ([@StealthyCoder](https://github.com/StealthyCoder))

## License

- *meta-glowworm* is licensed under the [MIT](COPYING.MIT) license.
- Software that a recipe downloads keeps its own license: `tailscale-bin` installs Tailscale's
  BSD-3-Clause binaries.

## What the layer adds

| Recipe | Applies | What it does |
| --- | --- | --- |
| `packagegroup-glowworm-gpu` | `ci/glowworm.yml` | Turnip (`mesa-vulkan-drivers`), `vulkan-loader` and `vulkan-tools` |
| `mesa` bbappend | `MACHINE = uno-q` | removes `opencl libclc gallium-llvm` from `PACKAGECONFIG`, so Mesa builds without LLVM, clang and Rust; `GLOWWORM_MESA_OPENCL = "1"` restores them |
| `os-release` bbappend | `MACHINE = uno-q` | adds `VARIANT="Glowworm"` and `VARIANT_ID="glowworm"` and sets `PRETTY_NAME`; `NAME` and `ID` stay the distro's |
| `uno-q-clock` | `ci/glowworm.yml` | starts `aktualizr-lite`, `fioconfig` and `tailscaled` after NTP and retries `timesyncd` after 5 s; the kernel no longer sets the clock from the never-set RTC (`CONFIG_RTC_HCTOSYS` is off in the pinned `meta-qcom-arduino`), which replaces this recipe's old `rtc_pm8xxx` blacklist ([docs/uno-q-clock.md](docs/uno-q-clock.md)) |
| `linux-arduino` bbappend | `MACHINE = uno-q` | adds a config fragment with `CONFIG_GPIO_CDEV_V1=y`, which `linux-arduino` 7.2 no longer enables and which the OpenOCD of older `glowworm-mcu` images needs; to be deleted once the MCU image's OpenOCD is shown to work without it |
| `dev-access` | `IMAGE_INSTALL` | NetworkManager Wi-Fi profile, regulatory domain and a root SSH key (key login only), from files named in `local.yml` |
| `uno-q-memhole` | `IMAGE_INSTALL` | boot-time oneshot that soft-offlines the RAM pages `0x7a000000-0x7c9fefff` |
| `tailscale-bin` | `IMAGE_INSTALL` | Tailscale's prebuilt static aarch64 binaries, pinned by sha256, and the systemd unit |
| `ghostty-terminfo` | `IMAGE_INSTALL` | the `xterm-ghostty` terminfo entry, compiled from `files/xterm-ghostty.terminfo` |

`dev-access` holds no secret: it installs the files that `local.yml` points at. The image built
from it does carry the Wi-Fi passphrase.

`uno-q-memhole` works around [meta-qcom-arduino#16](https://github.com/qualcomm-linux/meta-qcom-arduino/issues/16):
boards with the original edk2 boot firmware list that window as RAM and fault under memory load.
OTA does not update boot firmware, so it matters for boards flashed before the layers moved to
Arduino's ABL firmware `251020`.

`tailscale-bin` installs the binaries and the unit. The board still logs in once with
`tailscale up`, and a USB reflash wipes that login.

## Building

```sh
git clone https://github.com/StealthyCoder/meta-glowworm.git
cd meta-glowworm
kas build ci/glowworm.yml
```

kas checks the layers out next to the clone and builds `core-image-full-cmdline` for the `uno-q`
machine and the `qcom-distro-sota` distro. The image lands in `build/tmp/deploy/images/uno-q/`.
Point `DL_DIR` and `SSTATE_DIR` at directories outside the clone to share caches between builds. A
cold build compiles the whole OS and takes hours; with a warm sstate cache it takes minutes.
`KAS_CLONE_DEPTH=1` makes kas fetch shallow clones; keep it set for every kas run in the same
directory, because a later run without it cannot verify the pinned commits against a shallow
history.

`ci/glowworm.lock.yml` pins `meta-foundries`, and `meta-foundries` pins the other layers in its own
lockfiles. Move the pin with `kas lock --update ci/glowworm.yml`.

For now `ci/glowworm.yml` also pins `meta-qcom`, `meta-qcom-distro` and `meta-qcom-arduino` itself, in an
`overrides:` block, to get the UNO Q RTC fix ([docs/uno-q-clock.md](docs/uno-q-clock.md)) before
`meta-foundries` does. It has to be there and not in `ci/glowworm.lock.yml`: kas lets the lockfile of an
included file win over this repo's lockfile, so a pin in `glowworm.lock.yml` is ignored without a
warning. Delete the block when `meta-foundries` pins `meta-qcom-arduino` at `4697cfa` or later. The image
also keeps the Arduino kernel (`linux-arduino`) through `ci/linux-arduino.yml`, because `meta-qcom-arduino`
now defaults the UNO Q to `linux-qcom-next`.

### Reaching the board: `local.yml`

The image from `ci/glowworm.yml` has no Wi-Fi profile and no SSH key. Flash it over USB; an OTA of
it leaves a board that is reached over the network unreachable. For a bench board, copy the
credential-free template and build with it:

```sh
cp local.yml.example local.yml    # git-ignored; edit the paths
kas build ci/glowworm.yml:local.yml
```

**Keep an image built with `local.yml` off update servers and factories.** It carries the Wi-Fi
passphrase.

## Layer Dependencies

This layer depends on:

```text
URI: https://github.com/foundriesio/meta-foundries
layers: meta-foundries
branch: main
revision: see ci/glowworm.lock.yml
```

`meta-foundries` brings its own dependencies (see its README). The `uno-q` machine and the
`qcom-distro-sota` distro come from `meta-qcom`, `meta-qcom-distro` and `meta-qcom-arduino`, which
`ci/uno-q.yml` of `meta-foundries` pulls in.

The layer recommends two more:

```text
URI: https://git.openembedded.org/meta-openembedded
layers: meta-networking (collection "networking-layer")
branch: master
revision: HEAD
```

`dev-access` needs NetworkManager from `meta-networking`.

```text
URI: https://github.com/qualcomm-linux/meta-qcom-arduino
layers: meta-qcom-arduino (collection "qcom-arduino")
branch: main
revision: HEAD
```

It provides the `uno-q` machine that the recipes of this layer are compatible with.

## Adding the meta-glowworm layer to your build

Run `bitbake-layers add-layer meta-glowworm` after `meta-foundries` is in `bblayers.conf`.

## Contributing

Please submit patches with a GitHub pull request: fork the repo, create a branch, do the work,
rebase on `main`, and open the pull request.

Commits follow the conventions of `meta-foundries`: a `component: summary` subject, a body that
explains the reason before the change, lines of 72 characters or fewer, and a `Signed-off-by`
trailer (`git commit -s`).

The layer builds the UNO Q image with `kas`; it has not been tried with `kas-container`.
