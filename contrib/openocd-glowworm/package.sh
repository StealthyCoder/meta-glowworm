#!/bin/sh
# Runs inside the build container, after `make install DESTDIR=/pkg`. Checks what was built, then makes /out/openocd-glowworm_*.deb.
# Every check fails the build: a deb that quietly lacks the driver is worse than no deb.
set -eu

pkg=/pkg
out=/out
bin=$pkg/usr/bin/openocd
scripts=$pkg/usr/share/openocd/scripts
die() { echo "package.sh: $*" >&2; exit 1; }

strip --strip-unneeded "$bin"

echo "== the linuxgpiod driver is compiled in"
res=$("$bin" -s "$scripts" -c 'adapter driver linuxgpiod' -c 'shutdown' 2>&1) || { echo "$res"; die "openocd refuses 'adapter driver linuxgpiod'"; }
echo "$res" | grep -qi 'not found\|not available\|unknown' && { echo "$res"; die "no linuxgpiod driver in this build"; }
"$bin" --version 2>&1 | head -n 1

echo "== it links libgpiod 2.x (soname libgpiod.so.3), not 1.x (libgpiod.so.2)"
ldd "$bin"
ldd "$bin" | grep -q 'libgpiod\.so\.3' || die "not linked against libgpiod.so.3"
ldd "$bin" | grep -q 'libgpiod\.so\.2' && die "linked against libgpiod 1.x"

echo "== it needs no newer glibc than the glowworm-mcu base image (2.36)"
max=$(objdump -T "$bin" | grep -o 'GLIBC_[0-9][0-9.]*' | sort -uV | tail -n 1)
echo "newest glibc symbol: $max"
[ "$(printf '%s\nGLIBC_2.36\n' "$max" | sort -V | tail -n 1)" = GLIBC_2.36 ] || die "needs $max, the base image has 2.36"

echo "== the libraries that are not already in the base image go along"
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
libdir=$pkg/usr/lib/$multiarch
mkdir -p "$libdir"
# libc, libm, libgcc and friends are in debian:bookworm-slim already; everything else ldd finds is shipped, as a plain file under its soname.
ldd "$bin" | awk '/=> \//{print $3}' | while read -r lib; do
    case "$(basename "$lib")" in
        libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libgcc_s.so.*|libstdc++.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$lib" "$libdir/$(basename "$lib")"
    echo "shipping $(basename "$lib")"
done

# Documentation is cut anyway by glowworm's `exclude`; leave it out of the package too.
rm -rf "$pkg/usr/share/doc" "$pkg/usr/share/man" "$pkg/usr/share/info"

echo "== the deb"
cd /src
date=$(git log -1 --format=%cd --date=format:%Y%m%d)
short=$(git rev-parse --short=8 HEAD)
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
export SOURCE_DATE_EPOCH
arch=$(dpkg --print-architecture)
ver="0.12.0+git${date}.${short}-1"
mkdir -p "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<EOF
Package: openocd-glowworm
Version: $ver
Architecture: $arch
Maintainer: glowworm <glowworm@localhost>
Section: electronics
Priority: optional
Description: OpenOCD master ($short) with the libgpiod v2 linuxgpiod driver
 Built for the glowworm-mcu image of the Arduino UNO Q: SWD to the STM32U585 over two GPIO lines. GPL-2.0-or-later,
 source: https://github.com/openocd-org/openocd at commit $(git rev-parse HEAD).
EOF
find "$pkg" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
dpkg-deb --root-owner-group -Zxz --build "$pkg" "$out/openocd-glowworm_${ver}_${arch}.deb"
dpkg-deb -I "$out/openocd-glowworm_${ver}_${arch}.deb" | head -n 12
dpkg-deb -c "$out/openocd-glowworm_${ver}_${arch}.deb" | grep -E 'usr/bin/openocd|\.so' || true
ar t "$out/openocd-glowworm_${ver}_${arch}.deb"   # glowworm reads the member data.tar.xz
ar t "$out/openocd-glowworm_${ver}_${arch}.deb" | grep -qx 'data.tar.xz' || die "the deb has no data.tar.xz member"
