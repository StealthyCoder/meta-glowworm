# syntax=docker/dockerfile:1
#
# OpenOCD from a pinned upstream commit, with the linuxgpiod driver built on libgpiod 2.x, packaged as a .deb in the shape
# glowworm's `unpack_arm64` reads (an ar archive whose data.tar.xz holds ./usr/...). See README.md for why.
#
# The base is the SAME image the glowworm-mcu container runs on (container/mcu/Dockerfile in the glowworm repo): the binary
# is linked against that image's glibc (2.36), so it runs there. Keep the two digests equal.
ARG BASE=debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587

FROM ${BASE} AS build

# The upstream commit to build. Master has libgpiod v2 support since 2025-09-27 (c92cc6b5); there is no release with it yet
# (the last one is v0.12.0, 2023). Bump this on purpose, and bump the sha256 pinned in glowworm's app.toml with it.
ARG OPENOCD_REPO=https://github.com/openocd-org/openocd.git
ARG OPENOCD_COMMIT=4900bcdfc82848e9cfa7f895b39aca6b9ca4b911
# 0 = every core. Use 2 on a small machine such as the UNO Q itself.
ARG JOBS=0

# libgpiod 2.x for bookworm lives in bookworm-backports (2.1.3); OpenOCD's configure wants >= 2.0. libjim-dev (0.81) is the
# system Tcl that OpenOCD master uses by default (it needs >= 0.79).
RUN set -eux; \
    echo 'deb http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/backports.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates git build-essential autoconf automake libtool pkg-config texinfo \
        libjim-dev binutils dpkg-dev xz-utils; \
    apt-get install -y --no-install-recommends -t bookworm-backports libgpiod-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN set -eux; \
    git init -q .; \
    git remote add origin "$OPENOCD_REPO"; \
    git fetch -q --depth 1 origin "$OPENOCD_COMMIT"; \
    git checkout -q FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "$OPENOCD_COMMIT"

# --enable-linuxgpiod makes configure fail instead of quietly leaving the driver out. The other adapters (USB, FTDI, J-Link ...)
# are only built when their -dev packages are installed, and they are not: this board needs the bit-bang driver and nothing else.
RUN set -eux; \
    ./bootstrap; \
    mkdir /build; cd /build; \
    /src/configure --prefix=/usr --enable-linuxgpiod --disable-werror \
        --disable-doxygen-html --disable-doxygen-pdf; \
    make -j"$([ "$JOBS" -gt 0 ] && echo "$JOBS" || nproc)"; \
    make install DESTDIR=/pkg

COPY package.sh /package.sh
RUN set -eux; mkdir /out; sh /package.sh

# `docker build --output type=local,dest=DIR --target export .` writes the .deb and its checksum into DIR.
FROM scratch AS export
COPY --from=build /out/ /
