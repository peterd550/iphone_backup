# Optimized iPhone Backup + Parallel Cleanup Script (DCIM only)

Summary
-------
This script mounts an iPhone, copies the `DCIM` folder into a dated backup, optionally calculates file hashes, deletes old photos from the device (based on a cutoff date), removes empty `DCIM` directories, and generates an HTML report + log. It supports a dry-run mode to preview deletions.

Prerequisites
-------------
- `bash` (the script is a bash script)
- `ifuse` (to mount the iPhone)
- `rsync` (for copying files)
- `sha256sum` (recommended; used to update the hash DB)
- `exiftool` (optional; used to read EXIF dates for better precision)
- `google-chrome` or `google-chrome-stable` (optional; used to auto-open the HTML report)
- `sudo` access for mount/unmount and deletion operations

Configuration (edit at top of `iphone_backup.sh`)
------------------------------------------------
- `DRY_RUN` — set to `true` to avoid deleting files or creating the final archive; defaults to `false`.
- `MOUNT_POINT` — where the phone is mounted (e.g. `/media/pete/New Volume/iphone`).
- `BACKUP_ROOT` — root path where backups, reports, logs, and temporary dirs are stored.
- `PARALLEL_CORES` — number of parallel workers used for hashing/deletion.
- `CUTOFF_DATE_IPHONE` — numeric epoch cutoff used to select files to delete (script sets to 12 months ago by default).
- `HASH_DB`, `TMP_BACKUP_DIR`, `ARCHIVE_NAME`, `REPORT_FILE`, `DELETED_FILES_LIST`, `LOG_FILE` — paths derived from `BACKUP_ROOT`.

Usage
-----
1. Make the script executable (if not already):

```bash
chmod +x iphone_backup.sh
```

2. Run the script (you will be prompted for `sudo` where needed):

```bash
./iphone_backup.sh
```

3. Test with a dry run (two options):

- Edit the top of `iphone_backup.sh` and set `DRY_RUN=true`, then run the script.
- Or run a temporary modified copy without changing the file:

```bash
sed 's/^DRY_RUN=.*/DRY_RUN=true/' iphone_backup.sh > /tmp/iphone_backup_dry.sh && bash /tmp/iphone_backup_dry.sh
```

Tips
----
- To change deletion age, edit the `CUTOFF_DATE_IPHONE` assignment (e.g. use `date -d "6 months ago" +%s`).
- Increase or decrease `PARALLEL_CORES` based on your CPU to speed up hashing/deletions.
- If you want EXIF-based timestamps for deletion, install `exiftool`; the script auto-detects it.
- The script appends logs to `LOG_FILE` and records deleted/dry-run items in `DELETED_FILES_LIST`.

Safety & Troubleshooting
------------------------
- Always run a dry run first (`DRY_RUN=true`) to verify which files would be deleted.
- Ensure `MOUNT_POINT` and `BACKUP_ROOT` are accessible and have sufficient free space.
- If the `DCIM` folder is not found, check that `ifuse` mounted the device successfully and that the phone is unlocked/trusted.
- If Chrome doesn't open automatically, open the generated HTML report at the path printed in the log.

Examples
--------
- Full backup + cleanup (interactive sudo prompts as needed):

```bash
./iphone_backup.sh
```

- Dry run (preview deletions, no archive):

```bash
sed 's/^DRY_RUN=.*/DRY_RUN=true/' iphone_backup.sh > /tmp/iphone_backup_dry.sh && bash /tmp/iphone_backup_dry.sh
```

License
-------
See the project `LICENSE` file for licensing details.

Contact
-------
For changes or improvements (CLI flags, environment overrides, etc.), edit `iphone_backup.sh` or open an issue in your project tracker.
