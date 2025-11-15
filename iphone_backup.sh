#!/bin/bash -xe
set -euo pipefail
IFS=$'\n\t'

# =====================================================================
# Optimized iPhone Backup + Parallel Cleanup Script
# - Mounts iPhone at /mnt/iphone
# - Deduplicates with parallel hashing
# - Uses rsync for fast backup
# - Batch EXIF parsing
# - Parallel deletion of old files
# - Dry run mode supported
# - Live progress and desktop notifications
# =====================================================================

# -------------------------
# Configuration
# -------------------------
DRY_RUN=true                     # true = dry run, false = actual backup & deletion
MOUNT_POINT="/mnt/iphone"
BACKUP_ROOT="/mnt/IPHONE_Backups"
HASH_DB="$BACKUP_ROOT/photo_hashes.txt"
TMP_BACKUP_DIR="$BACKUP_ROOT/tmp_backup_$(date +%Y-%m-%d_%H-%M)"
CUTOFF_DATE_IPHONE=$(date -d "12 months ago" +%s)
ARCHIVE_NAME="$BACKUP_ROOT/Archive_$(date +%Y-%m-%d_%H-%M).tar.gz"
PARALLEL_CORES=4                 # Number of parallel processes for hashing & deletion

# Ensure required directories exist
sudo mkdir -p "$MOUNT_POINT"
sudo mkdir -p "$BACKUP_ROOT"
touch "$HASH_DB"
mkdir -p "$TMP_BACKUP_DIR"

# -------------------------
# Mount iPhone (modern ifuse)
# -------------------------
echo "🔌 Mounting iPhone at $MOUNT_POINT..."
if mount | grep -q "$MOUNT_POINT"; then
    echo "[✓] Already mounted."
else
    sudo ifuse "$MOUNT_POINT"
fi

# -------------------------
# Backup new files using rsync
# -------------------------
echo "📦 Backing up new photos/videos..."
if [ "$DRY_RUN" = true ]; then
    rsync -avn --progress "$MOUNT_POINT"/ "$TMP_BACKUP_DIR"/
else
    rsync -a --ignore-existing --progress "$MOUNT_POINT"/ "$TMP_BACKUP_DIR"/
fi

# -------------------------
# Update hash DB using parallel hashing
# -------------------------
echo "🔍 Calculating file hashes for deduplication..."
find "$TMP_BACKUP_DIR" -type f -print0 | xargs -0 -n1 -P "$PARALLEL_CORES" sha256sum | while read -r hash path; do
    if ! grep -qx "$hash" "$HASH_DB"; then
        [ "$DRY_RUN" = false ] && echo "$hash" >> "$HASH_DB"
    fi
done

# -------------------------
# Create archive if not dry run
# -------------------------
if [ "$DRY_RUN" = false ]; then
    echo "📦 Creating archive: $ARCHIVE_NAME"
    cd "$BACKUP_ROOT"
    tar -czf "$ARCHIVE_NAME" "$(basename "$TMP_BACKUP_DIR")" 2>/dev/null
    rm -rf "$TMP_BACKUP_DIR"
    echo "✅ Backup complete: $ARCHIVE_NAME"
    notify-send "iPhone Backup Complete" "Backup saved: $(basename "$ARCHIVE_NAME")"
else
    echo "📦 Dry run complete: files would have been archived."
fi

# -------------------------
# Delete files older than 12 months (parallel)
# -------------------------
echo "🧹 Deleting iPhone files older than 12 months..."
EXIF_METADATA=$(exiftool -r -DateTimeOriginal -CreateDate -MediaCreateDate -QuickTime:CreateDate "$MOUNT_POINT" 2>/dev/null)

delete_file() {
    local file="$1"
    local file_date="$2"
    if [ "$DRY_RUN" = true ]; then
        echo "🗑 Would delete: $file (Date: $file_date)"
    else
        sudo rm -f "$file"
        echo "🗑 Deleted: $file"
    fi
}
export -f delete_file
export DRY_RUN

DELETE_LIST="$BACKUP_ROOT/files_to_delete.txt"
> "$DELETE_LIST"

while IFS= read -r -d '' file; do
    FILE_DATE_RAW=$(grep -F "$file" <<< "$EXIF_METADATA" | head -n1 | awk '{print $2}' | sed 's/:/-/; s/:/-/')
    [ -z "$FILE_DATE_RAW" ] && FILE_DATE_RAW=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
    [ -z "$FILE_DATE_RAW" ] && continue
    FILE_DATE_SECONDS=$(date -d "$FILE_DATE_RAW" +%s 2>/dev/null || echo 0)
    if (( FILE_DATE_SECONDS > 0 && FILE_DATE_SECONDS < CUTOFF_DATE_IPHONE )); then
        echo "$file|$FILE_DATE_RAW" >> "$DELETE_LIST"
    fi
done < <(find "$MOUNT_POINT" -type f -print0)

TOTAL_DELETE=$(wc -l < "$DELETE_LIST")
echo "Total files marked for deletion: $TOTAL_DELETE"

cat "$DELETE_LIST" | xargs -P "$PARALLEL_CORES" -I{} bash -c 'IFS="|"; read f d <<< "{}"; delete_file "$f" "$d"'

[ "$DRY_RUN" = false ] && notify-send "iPhone Cleanup Complete" "Deleted $TOTAL_DELETE photos/videos older than 12 months from iPhone."
[ "$DRY_RUN" = true ] && echo "✅ Dry run complete: no files deleted."

# -------------------------
# Unmount iPhone
# -------------------------
sudo fusermount3 -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null
echo "📴 iPhone unmounted."

exit 0
