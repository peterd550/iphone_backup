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

CLI Options
-----------
You can now pass options directly via command line:

- `--dry-run` — preview changes without deleting files or creating archive.
- `--cores N` — set number of parallel workers (default: 4).
- `--help` — show usage help.

Configuration (edit at top of `iphone_backup.sh`)
------------------------------------------------
For settings not exposed as CLI flags, edit the script directly:

- `MOUNT_POINT` — where the phone is mounted (e.g. `/media/pete/New Volume/iphone`).
- `BACKUP_ROOT` — root path where backups, reports, logs, and temporary dirs are stored.
- `CUTOFF_DATE_IPHONE` — numeric epoch cutoff used to select files to delete (script sets to 12 months ago by default).
- `HASH_DB`, `TMP_BACKUP_DIR`, `ARCHIVE_NAME`, `REPORT_FILE`, `DELETED_FILES_LIST`, `LOG_FILE` — paths derived from `BACKUP_ROOT`.

Usage
-----
1. Make the script executable (if not already):

```bash
chmod +x iphone_backup.sh
```

2. Run the script with optional flags (you will be prompted for `sudo` where needed):

```bash
./iphone_backup.sh
```

3. Test with a dry run:

```bash
./iphone_backup.sh --dry-run
```

4. Run with custom parallelism:

```bash
./iphone_backup.sh --cores 8
```

5. Combine flags:

```bash
./iphone_backup.sh --dry-run --cores 8
```

Tips
----
- To change deletion age, edit the `CUTOFF_DATE_IPHONE` assignment (e.g. use `date -d "6 months ago" +%s`).
- Use `--cores N` to adjust parallelism based on your CPU (e.g. `--cores 8` for faster hashing/deletions).
- If you want EXIF-based timestamps for deletion, install `exiftool`; the script auto-detects it.
- The script appends logs to `LOG_FILE` and records deleted/dry-run items in `DELETED_FILES_LIST`.
- The script will automatically unmount the iPhone on exit (normal or interrupted).
- If required dependencies are missing, the script will report them and exit with code 1.

Safety & Troubleshooting
------------------------
- Always run a dry run first (`--dry-run` flag) to verify which files would be deleted.
- Ensure `MOUNT_POINT` and `BACKUP_ROOT` are accessible and have sufficient free space.
- If the `DCIM` folder is not found, check that `ifuse` mounted the device successfully and that the phone is unlocked/trusted.
- If Chrome doesn't open automatically, open the generated HTML report at the path printed in the log.
- If you press Ctrl+C during execution, the script will gracefully unmount the iPhone before exiting.

Examples
--------
- Full backup + cleanup (interactive sudo prompts as needed):

```bash
./iphone_backup.sh
```

- Dry run (preview deletions, no archive):

```bash
./iphone_backup.sh --dry-run
```

- Dry run with increased parallelism:

```bash
./iphone_backup.sh --dry-run --cores 8
```

- Run with custom core count (for faster performance on high-CPU systems):

```bash
./iphone_backup.sh --cores 16
```

- Show help:

```bash
./iphone_backup.sh --help
```

License
-------
See the project `LICENSE` file for licensing details.

Contact
-------
For bug reports or feature requests, open an issue in your project tracker.
