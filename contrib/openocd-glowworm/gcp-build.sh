#!/usr/bin/env bash
# Builds the OpenOCD .deb on a throwaway arm64 VM in GCP: create it, build there, copy the .deb back, delete the VM.
#
#   ./gcp-build.sh --project PROJECT [--zone ZONE] [--machine-type TYPE] [--keep] [--dry-run]
#   ./gcp-build.sh --project PROJECT --cleanup     # delete leftover VMs this script made (label purpose=openocd-glowworm)
#
# --project is required on purpose: the script never falls back to gcloud's default project, which on a work laptop can be
# a production one. Only public things go to the VM (this directory, then OpenOCD from GitHub and Debian's packages).
# Expect about 5 minutes and cents of compute. The VM deletes itself after 2 hours even if this script dies
# (--max-run-duration), and the script deletes it on exit unless you pass --keep.
set -euo pipefail
cd "$(dirname "$0")"

project=
zone=europe-west4-a            # Tau T2A (arm64) runs in europe-west4-a/b; check with: gcloud compute machine-types list --filter='name~t2a' --project P
machine=t2a-standard-4
keep=0 dry=0 cleanup=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project) project=$2; shift 2 ;;
        --zone) zone=$2; shift 2 ;;
        --machine-type) machine=$2; shift 2 ;;
        --keep) keep=1; shift ;;
        --dry-run) dry=1; shift ;;
        --cleanup) cleanup=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$project" ] || { echo "gcp-build.sh: --project is required (it does not use gcloud's default project)" >&2; exit 2; }

run() { echo "+ $*" >&2; [ "$dry" = 1 ] || "$@"; }

if [ "$cleanup" = 1 ]; then
    echo "VMs labelled purpose=openocd-glowworm in $project:"
    gcloud compute instances list --project "$project" --filter='labels.purpose=openocd-glowworm' --format='value(name,zone)' |
    while read -r n z; do
        [ -n "$n" ] || continue
        run gcloud compute instances delete "$n" --project "$project" --zone "${z##*/}"
    done
    exit 0
fi

vm=openocd-glowworm-build-$(date +%y%m%d-%H%M%S)
gc=(--project "$project" --zone "$zone")

delete_vm() {
    if [ "$keep" = 1 ]; then
        echo "kept $vm (delete it with: gcloud compute instances delete $vm --project $project --zone $zone)" >&2
    else
        echo "deleting $vm ..." >&2
        run gcloud compute instances delete "$vm" "${gc[@]}" --quiet || echo "!! could not delete $vm: delete it yourself" >&2
    fi
}

# Create first, then arm the trap, so that a failed create does not try to delete something that is not there.
run gcloud compute instances create "$vm" "${gc[@]}" \
    --machine-type "$machine" \
    --image-family debian-12-arm64 --image-project debian-cloud \
    --boot-disk-size 30GB \
    --labels purpose=openocd-glowworm \
    --max-run-duration 2h --instance-termination-action DELETE
trap delete_vm EXIT

echo "waiting for ssh ..." >&2
if [ "$dry" = 0 ]; then
    for i in $(seq 1 30); do
        gcloud compute ssh "$vm" "${gc[@]}" --command true >/dev/null 2>&1 && break
        [ "$i" = 30 ] && { echo "ssh never came up" >&2; exit 1; }
        sleep 10
    done
fi

run gcloud compute ssh "$vm" "${gc[@]}" --command 'sudo apt-get update -qq && sudo apt-get install -y -qq docker.io >/dev/null && mkdir -p openocd-glowworm'
run gcloud compute scp "${gc[@]}" Dockerfile package.sh build.sh "$vm:openocd-glowworm/"
run gcloud compute ssh "$vm" "${gc[@]}" --command 'cd openocd-glowworm && sudo ./build.sh --out out'

mkdir -p out
run gcloud compute scp "${gc[@]}" "$vm:openocd-glowworm/out/openocd-glowworm_*.deb" "$vm:openocd-glowworm/out/SHA256SUMS" out/
echo
echo "done: $(pwd)/out" >&2
[ "$dry" = 1 ] || { cat out/SHA256SUMS; }
