#!/bin/bash -xe
set -euo pipefail
IFS=$'\n\t'

# =====================================================================
# Optimized iPhone Backup + Parallel Cleanup Script (DCIM only)
# - Mounts iPhone at MOUNT_POINT
# - Uses rsync to backup DCIM
# - Parallel hashing (optional)
# - Batch EXIF parsing (if available)
# - Parallel deletion of old files (null-safe)
# - Dry run mode supported
# =====================================================================

# -------------------------
# Prerequisites (uncomment if you want the script to install them)
# -------------------------
sudo apt -y update
sudo apt -y install ifuse libimobiledevice6 libimobiledevice-utils fuse3 rsync exiftool notify-osd dbus-x11 parallel

# -------------------------
# Configuration
# -------------------------
DRY_RUN=false               # true = dry run, false = actual backup & deletion
MOUNT_POINT="/media/pete/New Volume/iphone"
BACKUP_ROOT="/media/pete/New Volume/IPHONE_Backups"
DCIM_FOLDER="$MOUNT_POINT/DCIM"  # Only backup DCIM folder
HASH_DB="$BACKUP_ROOT/photo_hashes.txt"
TMP_BACKUP_DIR="$BACKUP_ROOT/tmp_backup_$(date +%Y-%m-%d_%H-%M)"
CUTOFF_DATE_IPHONE=$(date -d "12 months ago" +%s)
ARCHIVE_NAME="$BACKUP_ROOT/Archive_$(date +%Y-%m-%d_%H-%M).tar.gz"
PARALLEL_CORES=4                 # Number of parallel processes for hashing & deletion

# -------------------------
# Ensure required directories exist
# -------------------------
sudo mkdir -p "$MOUNT_POINT"
sudo mkdir -p "$BACKUP_ROOT"
touch "$HASH_DB"
mkdir -p "$TMP_BACKUP_DIR"

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

# verify DCIM exists
if [ ! -d "$DCIM_FOLDER" ]; then
    echo "[ERROR] DCIM folder not found at: $DCIM_FOLDER"
    echo "Make sure the phone is unlocked, trusted, and the mount path is correct."
    exit 2
fi

# -------------------------
# Backup DCIM folder using rsync
# -------------------------
echo "📦 Backing up DCIM folder..."
if [ "$DRY_RUN" = true ]; then
    rsync -avn --progress --modify-window=1 "$DCIM_FOLDER"/ "$TMP_BACKUP_DIR"/
else
    rsync -a --ignore-existing --progress --modify-window=1 "$DCIM_FOLDER"/ "$TMP_BACKUP_DIR"/
fi

# -------------------------
# Update hash DB using parallel hashing (optional)
# -------------------------
if command -v sha256sum >/dev/null 2>&1; then
    echo "🔍 Calculating file hashes for deduplication..."
    find "$TMP_BACKUP_DIR" -type f -print0 \
        | xargs -0 -n1 -P "$PARALLEL_CORES" -I{} sha256sum "{}" \
        | while read -r hash path; do
            # ensure the hash DB line format is only the hash (one per line)
            if ! grep -qxF "$hash" "$HASH_DB"; then
                [ "$DRY_RUN" = false ] && echo "$hash" >> "$HASH_DB"
            fi
        done
else
    echo "[!] sha256sum not found; skipping hash DB update."
fi

# -------------------------
# Create archive if not dry run
# -------------------------
if [ "$DRY_RUN" = false ]; then
    echo "📦 Creating archive: $ARCHIVE_NAME"
    cd "$BACKUP_ROOT"
    tar -czf "$ARCHIVE_NAME" "$(basename "$TMP_BACKUP_DIR")"
    rm -rf "$TMP_BACKUP_DIR"
    echo "✅ Backup complete: $ARCHIVE_NAME"
    command -v notify-send >/dev/null 2>&1 && notify-send "iPhone Backup Complete" "Backup saved: $(basename "$ARCHIVE_NAME")"
else
    echo "📦 Dry run complete: files would have been archived (no archive created)."
fi

# -------------------------
# Delete files older than 12 months (parallel, null-safe)
# -------------------------
echo "🧹 Deleting old photos/videos from iPhone (DCIM only)..."

# Build EXIF metadata once (if exiftool exists). This may be large but faster than calling exiftool per file.
EXIF_AVAILABLE=false
if command -v exiftool >/dev/null 2>&1; then
    EXIF_AVAILABLE=true
    # produce a mapping of filename -> date in a safer format
    # exiftool -T prints tab-separated values per file: filename<TAB>tagvalue
    # We'll extract DateTimeOriginal/CreateDate/ModifyDate precedence per file using exiftool's -if and -p options is complex,
    # so instead we'll rely on exiftool -j (JSON) and parse per-file when needed.
    # To keep memory lower, we won't store huge JSON — we'll call exiftool for each candidate file below only when needed.
fi

# prepare a null-delimited delete list
DELETE_LIST_NULL="$BACKUP_ROOT/files_to_delete.null"
: > "$DELETE_LIST_NULL"

# iterate DCIM files null-safely
while IFS= read -r -d '' file; do
    # try to get EXIF date (DateTimeOriginal/CreateDate/MediaCreateDate/QuickTime:CreateDate) if exiftool is available
    FILE_DATE_RAW=""
    if [ "$EXIF_AVAILABLE" = true ]; then
        # call exiftool for this file only (faster than grepping a huge pre-built blob)
        # try the most common tags in order
        FILE_DATE_RAW=$(exiftool -s -s -s -DateTimeOriginal -CreateDate -MediaCreateDate -QuickTime:CreateDate "$file" 2>/dev/null | sed -n '1p' || true)
        # exiftool returns formats like "YYYY:MM:DD HH:MM:SS" — convert first two ":" to "-" and get date portion
        if [ -n "$FILE_DATE_RAW" ]; then
            FILE_DATE_RAW=$(echo "$FILE_DATE_RAW" | awk '{print $1}' | sed 's/:/-/; s/:/-/')
        fi
    fi

    # fallback to file modification date if no exif date
    if [ -z "$FILE_DATE_RAW" ]; then
        # get file mtime in YYYY-MM-DD
        FILE_DATE_RAW=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || true)
    fi

    [ -z "$FILE_DATE_RAW" ] && continue

    FILE_DATE_SECONDS=$(date -d "$FILE_DATE_RAW" +%s 2>/dev/null || echo 0)
    if (( FILE_DATE_SECONDS > 0 && FILE_DATE_SECONDS < CUTOFF_DATE_IPHONE )); then
        # append null-delimited entry: filepath|date\0
        printf '%s|%s\0' "$file" "$FILE_DATE_RAW" >> "$DELETE_LIST_NULL"
    fi
done < <(find "$DCIM_FOLDER" -type f -print0)

# count entries
TOTAL_DELETE=$(tr -cd '\0' < "$DELETE_LIST_NULL" | wc -c || true)
echo "Total files marked for deletion: $TOTAL_DELETE"

# if zero, skip
if [ "$TOTAL_DELETE" -eq 0 ]; then
    echo "[✓] No files to delete."
else
    # Run parallel deletion; xargs -0 will split on null and pass each chunk (file|date) to bash -c
    # we use -n1 to pass one entry per command, -P for parallelism
    cat "$DELETE_LIST_NULL" \
        | xargs -0 -n1 -P "$PARALLEL_CORES" -I{} bash -c 'IFS="|"; read -r f d <<< "{}"; 
            if [ "'"$DRY_RUN"'" = "true" ]; then
                printf "[DRY RUN] Would delete: %s (Date: %s)\n" "$f" "$d";
            else
                sudo rm -f -- "$f" && printf "Deleted: %s\n" "$f";
            fi
fi

# final notification
if [ "$DRY_RUN" = false ]; then
    echo "✅ Deletion complete: $TOTAL_DELETE files deleted."
    command -v notify-send >/dev/null 2>&1 && notify-send "iPhone Cleanup Complete" "Deleted $TOTAL_DELETE photos/videos older than 12 months from iPhone."
else
    echo "✅ Dry run complete: no files were deleted."
fi

delete_empty_dcim_folders() {
    ###DELETE EMPTY DCIM FOLDERS FUNCTION###
    ###DELETE EMPTY DCIM FOLDERS FUNCTION###
    ###DELETE EMPTY DCIM FOLDERS FUNCTION###
    sleep 10
    local dcim_path="${DCIM_FOLDER}"

    echo "🧹 Scanning for empty DCIM folders on iPhone..."

    # Find and remove empty folders
    empty_dirs=$(find "$dcim_path" -type d -empty 2>/dev/null)

    if [[ -z "$empty_dirs" ]]; then
        echo "✨ No empty DCIM folders found."
        return
    fi

    echo "📁 Empty folders found:"
    echo "$empty_dirs"

    echo "🗑️ Deleting empty folders..."
    while IFS= read -r dir; do
        rmdir "$dir" 2>/dev/null && \
        echo "   ✔ Removed: $dir" || \
        echo "   ⚠️ Failed to remove: $dir"
    done <<< "$empty_dirs"

    echo "✅ Empty DCIM folder cleanup complete!"
}

# -------------------------
# Unmount iPhone
# -------------------------
sudo fusermount3 -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null || true
echo "📴 iPhone unmounted."

exit 0
