#!/bin/bash


MOUNT_POINT="/media/pete/New Volume/iphone"
sudo mkdir -p "$MOUNT_POINT"
DCIM_FOLDER="$MOUNT_POINT/DCIM"

# -------------------------
# Mount iPhone (modern ifuse)
# -------------------------
echo "🔌 Mounting iPhone at $MOUNT_POINT..."
if mount | grep -qF "$MOUNT_POINT"; then
    echo "[✓] Already mounted."
else
    # ifuse may require the phone to be unlocked and trusted
    sudo ifuse "$MOUNT_POINT"
fi

ls -l "$DCIM_FOLDER"
cd "$DCIM_FOLDER"
du -shH ./*

# verify DCIM exists
if [ ! -d "$DCIM_FOLDER" ]; then
    echo "[ERROR] DCIM folder not found at: $DCIM_FOLDER"
    echo "Make sure the phone is unlocked, trusted, and the mount path is correct."
    exit 2
fi