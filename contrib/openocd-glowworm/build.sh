#!/usr/bin/env bash
# Builds the glowworm OpenOCD .deb with Docker. Run it on an arm64 machine (a GCP arm64 VM, see gcp-build.sh, or the UNO Q itself).
#
#   ./build.sh [--out DIR] [--jobs N]
#
# Writes DIR/openocd-glowworm_<version>_arm64.deb and DIR/SHA256SUMS, then prints the lines for glowworm's container/mcu/app.toml.
# OPENOCD_PLATFORM=linux/amd64 builds a TEST deb on an x86 machine: it proves the recipe compiles and the checks pass, but it
# is not for the board.
set -euo pipefail
cd "$(dirname "$0")"

out=out
jobs=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) out=$2; shift 2 ;;
        --jobs) jobs=$2; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

platform=${OPENOCD_PLATFORM:-linux/arm64}
host=$(uname -m)
if [ "$platform" = linux/arm64 ] && [ "$host" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "build.sh: this machine is $host and has no arm64 emulation (qemu binfmt)." >&2
    echo "  Run it on an arm64 machine: ./gcp-build.sh, or copy this directory to the UNO Q and run ./build.sh --jobs 2 there." >&2
    echo "  (OPENOCD_PLATFORM=linux/amd64 ./build.sh makes a test build that is not for the board.)" >&2
    exit 1
fi

mkdir -p "$out"
echo "building for $platform into $out ..."
DOCKER_BUILDKIT=1 docker build --platform "$platform" --build-arg "JOBS=$jobs" \
    --target export --output "type=local,dest=$out" .

(cd "$out" && sha256sum openocd-glowworm_*.deb > SHA256SUMS && cat SHA256SUMS)

deb=$(cd "$out" && ls openocd-glowworm_*.deb | head -n 1)
sum=$(cut -d' ' -f1 "$out/SHA256SUMS" | head -n 1)
case "$deb" in
    *_arm64.deb) ;;
    *) echo; echo "NOTE: $deb is a TEST build ($platform), not for the board." ; exit 0 ;;
esac
cat <<EOF

Publish $out/$deb at an HTTPS URL (a release asset of this repository, see README.md), then in glowworm's
container/mcu/app.toml make the OpenOCD line of unpack_arm64 this one (the deb carries its own libgpiod and libjim):

  "mcu.tar:opt/glowworm/mcu/openocd <URL>/$deb sha256:$sum",

See README.md for the checks on the board.
EOF
