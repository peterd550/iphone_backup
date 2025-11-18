#!/bin/bash


MOUNT_POINT="/media/pete/New Volume/iphone"

# -------------------------
# Unmount iPhone
# -------------------------
sudo fusermount3 -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null || true
echo "📴 iPhone unmounted."

exit 0