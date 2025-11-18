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
# - Parallel deletion of empty DCIM folders
# - Dry run mode supported
# - HTML report, Chrome auto-open, and log
# =====================================================================

# -------------------------
# Configuration
# -------------------------
DRY_RUN=false
MOUNT_POINT="/media/pete/New Volume/iphone"
BACKUP_ROOT="/media/pete/New Volume/IPHONE_Backups"
DCIM_FOLDER="$MOUNT_POINT/DCIM"
HASH_DB="$BACKUP_ROOT/photo_hashes.txt"
TMP_BACKUP_DIR="$BACKUP_ROOT/tmp_backup_$(date +%Y-%m-%d_%H-%M)"
CUTOFF_DATE_IPHONE=$(date -d "12 months ago" +%s)
ARCHIVE_NAME="$BACKUP_ROOT/Archive_$(date +%Y-%m-%d_%H-%M).tar.gz"
PARALLEL_CORES=4
REPORT_FILE="$BACKUP_ROOT/iPhone_backup_report_$(date +%Y-%m-%d_%H-%M).html"
DELETED_FILES_LIST="$BACKUP_ROOT/deleted_files.list"
LOG_FILE="$BACKUP_ROOT/iPhone_backup_$(date +%Y-%m-%d_%H-%M).log"

mkdir -p "$MOUNT_POINT" "$BACKUP_ROOT"
touch "$HASH_DB"
mkdir -p "$TMP_BACKUP_DIR"
: > "$DELETED_FILES_LIST"
: > "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# -------------------------
# Mount iPhone
# -------------------------
log "🔌 Mounting iPhone..."
if mount | grep -qF "$MOUNT_POINT"; then
    log "[✓] Already mounted."
else
    sudo ifuse "$MOUNT_POINT"
fi

[ ! -d "$DCIM_FOLDER" ] && { log "[ERROR] DCIM folder not found!"; exit 2; }

# -------------------------
# Backup DCIM folder
# -------------------------
log "📦 Backing up DCIM folder..."
if [ "$DRY_RUN" = true ]; then
    rsync -avn --progress --modify-window=1 "$DCIM_FOLDER"/ "$TMP_BACKUP_DIR"/ | tee -a "$LOG_FILE"
else
    rsync -a --ignore-existing --progress --modify-window=1 "$DCIM_FOLDER"/ "$TMP_BACKUP_DIR"/ | tee -a "$LOG_FILE"
fi

TOTAL_BACKUP_FILES=$(find "$TMP_BACKUP_DIR" -type f | wc -l || echo 0)
log "Total files backed up: $TOTAL_BACKUP_FILES"

# -------------------------
# Update hash DB
# -------------------------
if command -v sha256sum >/dev/null 2>&1; then
    log "🔍 Calculating file hashes..."
    find "$TMP_BACKUP_DIR" -type f -print0 \
        | xargs -0 -n1 -P "$PARALLEL_CORES" -I{} sha256sum "{}" \
        | while read -r hash path; do
            if ! grep -qxF "$hash" "$HASH_DB"; then
                [ "$DRY_RUN" = false ] && echo "$hash" >> "$HASH_DB"
            fi
        done
fi

# -------------------------
# Create archive
# -------------------------
if [ "$DRY_RUN" = false ]; then
    cd "$BACKUP_ROOT"
    tar -czf "$ARCHIVE_NAME" "$(basename "$TMP_BACKUP_DIR")"
    rm -rf "$TMP_BACKUP_DIR"
    log "✅ Backup complete: $ARCHIVE_NAME"
else
    log "📦 Dry run complete: no archive created"
fi

# -------------------------
# Delete old files
# -------------------------
EXIF_AVAILABLE=false
[ command -v exiftool >/dev/null 2>&1 ] && EXIF_AVAILABLE=true
DELETE_LIST_NULL="$BACKUP_ROOT/files_to_delete.null"
: > "$DELETE_LIST_NULL"

while IFS= read -r -d '' file; do
    FILE_DATE_RAW=""
    if [ "$EXIF_AVAILABLE" = true ]; then
        FILE_DATE_RAW=$(exiftool -s -s -s -DateTimeOriginal -CreateDate -MediaCreateDate -QuickTime:CreateDate "$file" 2>/dev/null | sed -n '1p' || true)
        [ -n "$FILE_DATE_RAW" ] && FILE_DATE_RAW=$(echo "$FILE_DATE_RAW" | awk '{print $1}' | sed 's/:/-/; s/:/-/')
    fi
    [ -z "$FILE_DATE_RAW" ] && FILE_DATE_RAW=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || true)
    [ -z "$FILE_DATE_RAW" ] && continue
    FILE_DATE_SECONDS=$(date -d "$FILE_DATE_RAW" +%s 2>/dev/null || echo 0)
    if (( FILE_DATE_SECONDS > 0 && FILE_DATE_SECONDS < CUTOFF_DATE_IPHONE )); then
        printf '%s|%s\0' "$file" "$FILE_DATE_RAW" >> "$DELETE_LIST_NULL"
    fi
done < <(find "$DCIM_FOLDER" -type f -print0)

TOTAL_DELETE=$(tr -cd '\0' < "$DELETE_LIST_NULL" | wc -c || echo 0)
log "Total old files marked for deletion: $TOTAL_DELETE"

if [ "$TOTAL_DELETE" -ne 0 ]; then
    cat "$DELETE_LIST_NULL" | xargs -0 -n1 -P "$PARALLEL_CORES" -I{} bash -c '
        IFS="|"; read -r f d <<< "{}"; 
        if [ "'"$DRY_RUN"'" = "true" ]; then
            echo "[DRY RUN]|$f|$d" | tee -a "'"$DELETED_FILES_LIST"'"; 
        else
            sudo rm -f -- "$f" && echo "[DELETED]|$f|$d" | tee -a "'"$DELETED_FILES_LIST"'";
        fi
    '
fi

# -------------------------
# Delete empty DCIM folders
# -------------------------
EMPTY_DIRS=$(find "$DCIM_FOLDER" -type d -empty 2>/dev/null)
TOTAL_EMPTY_FOLDERS=$(echo "$EMPTY_DIRS" | wc -l || echo 0)
while IFS= read -r dir; do
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN][EMPTY]|$dir|" | tee -a "$DELETED_FILES_LIST"
    else
        rmdir "$dir" 2>/dev/null && echo "[DELETED][EMPTY]|$dir|" | tee -a "$DELETED_FILES_LIST"
    fi
done <<< "$EMPTY_DIRS"

log "Empty DCIM folders processed: $TOTAL_EMPTY_FOLDERS"

# -------------------------
# Generate HTML report
# -------------------------
{
echo "<html><head><title>iPhone Backup Report</title>"
echo "<style>"
echo "body{font-family:Arial,sans-serif; background:#f5f5f5;}"
echo "table{border-collapse:collapse; width:100%;}"
echo "th,td{border:1px solid #ddd; padding:8px; text-align:left;}"
echo "th{background:#333; color:white;}"
echo ".deleted{background:#ffcccc;}"
echo ".dryrun{background:#ccffcc;}"
echo "</style></head><body>"
echo "<h2>iPhone Backup Report - $(date '+%Y-%m-%d %H:%M:%S')</h2>"
echo "<p>Total files backed up: $TOTAL_BACKUP_FILES</p>"
echo "<p>Total files marked for deletion: $TOTAL_DELETE</p>"
echo "<p>Empty DCIM folders processed: $TOTAL_EMPTY_FOLDERS</p>"

echo "<h3>Deleted / Dry-run files:</h3>"
echo "<table><tr><th>Status</th><th>File/Folder</th><th>Date</th></tr>"

while IFS='|' read -r status file date; do
    class="dryrun"
    [ "$status" = "[DELETED]" ] && class="deleted"
    echo "<tr class='$class'><td>$status</td><td>$file</td><td>$date</td></tr>"
done < "$DELETED_FILES_LIST"

echo "</table></body></html>"
} > "$REPORT_FILE"

log "HTML report generated: $REPORT_FILE"

# -------------------------
# Unmount iPhone
# -------------------------
sudo fusermount3 -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null || true
log "📴 iPhone unmounted."

# Open report in Chrome
if command -v google-chrome >/dev/null 2>&1; then
    google-chrome "$REPORT_FILE" &
elif command -v google-chrome-stable >/dev/null 2>&1; then
    google-chrome-stable "$REPORT_FILE" &
else
    log "[!] Chrome not found. Open report manually: $REPORT_FILE"
fi

log "✅ Backup script finished. Log file: $LOG_FILE"
exit 0
