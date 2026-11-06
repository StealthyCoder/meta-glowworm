#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Takes the free RAM pages of the physical window 0x7a000000-0x7c9fefff out of
# the allocator. The memory map lists them as RAM, but the top of this DRAM bank
# is not usable: writes raise a synchronous external abort (ESR 0x96000010) that
# kills whichever task owns the page, and the whole board when that is the
# kernel or an ostree install. Faults were seen at 0x7c9e0000, 0x7b8ff000 and
# 0x7b900000; the true floor is unknown, 0x7a000000 survived stress and OTA.
#
# The page flags of the whole window are read in one pass. Forking dd, od and tr
# for every page took 7 ms each, 77 s in all, and sysinit.target waits for this
# service, so NetworkManager, D-Bus and Docker started 85 s into the boot.

START_PFN=$((0x7a000))
END_PFN=$((0x7c9fe))
COUNT=$((END_PFN - START_PFN + 1))
OFFLINE=/sys/devices/system/memory/soft_offline_page
TAG=uno-q-memhole

if [ ! -w "$OFFLINE" ]; then
    logger -t "$TAG" "$OFFLINE is not writable, nothing offlined"
    exit 0
fi

# /proc/kpageflags has one 8 byte word per page; od prints one line for each.
# The loop is the last command of the pipeline, so it logs the totals itself,
# and its exit status is the one of the script.
dd if=/proc/kpageflags bs=8 skip="$START_PFN" count="$COUNT" 2> /dev/null | od -An -v -tx8 -w8 | {
    offlined=0
    poisoned=0
    skipped=0
    pfn=$START_PFN
    while read -r hex; do
        flags=$((0x${hex:-0}))
        if [ $(((flags >> 19) & 1)) -eq 1 ]; then
            poisoned=$((poisoned + 1))
        elif [ $(((flags >> 10) & 1)) -eq 1 ]; then
            if printf '0x%x' $((pfn * 4096)) 2> /dev/null > "$OFFLINE"; then
                offlined=$((offlined + 1))
            else
                skipped=$((skipped + 1))
                logger -t "$TAG" "offlining pfn $(printf '0x%x' "$pfn") failed"
            fi
        else
            skipped=$((skipped + 1))
            logger -t "$TAG" "pfn $(printf '0x%x' "$pfn") is in use, left alone"
        fi
        pfn=$((pfn + 1))
    done

    logger -t "$TAG" "pages offlined: $offlined, already poisoned: $poisoned, skipped: $skipped"
    if [ "$pfn" -le "$END_PFN" ]; then
        logger -t "$TAG" "read the flags of $((pfn - START_PFN)) of $COUNT pages from /proc/kpageflags"
        exit 1
    fi
}
