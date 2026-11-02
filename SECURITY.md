# Security Policy

## Reporting a vulnerability

Please report a vulnerability privately through GitHub: open the **Security** tab of this
repository and choose **Report a vulnerability**. Include:

- a description of the vulnerability
- steps to reproduce
- the affected commit or release
- the potential impact

A vulnerability that is already public, for example one with a released CVE number, can be reported
as a regular [GitHub issue](../../issues/new).

## Scope

This layer builds images and installs third-party software into them. These parts deserve a look:

- `tailscale-bin` installs Tailscale's prebuilt binaries, pinned by sha256.
- `dev-access` installs a root SSH key (key login only) and a Wi-Fi profile from files that the
  builder names in `local.yml`. The layer holds no secret; an image built with `local.yml` carries
  the Wi-Fi passphrase and has to stay off update servers and factories.
