# iPhone Backup & Cleanup Script for Ubuntu

A high-performance, safe, and fully automated script to **backup photos and videos from your iPhone** to an Ubuntu system and **delete old files from the iPhone**.  

This script mounts your iPhone via USB, backs up new photos/videos to a **timestamped archive**, deduplicates files, and deletes media older than 12 months — all while supporting a **dry run mode** for safe testing.

---

## **Features**

- ✅ Mounts iPhone at `/mnt/iphone` using `ifuse`
- ✅ Backs up only **new photos/videos** using `rsync` for speed
- ✅ Deduplicates files using **SHA256 hashes** with **parallel hashing**
- ✅ Creates **timestamped `.tar.gz` archives** in `/mnt/IPHONE_Backups`
- ✅ Deletes files older than **12 months** from the iPhone using **batch EXIF parsing**
- ✅ Supports **dry run mode** to preview actions without changing anything
- ✅ Performs **parallel deletion** for faster cleanup
- ✅ Live progress display and desktop notifications
- ✅ Fully optimized for **large iPhone libraries**

---

## **Requirements**

- Ubuntu 24.04 (or similar Linux distribution)
- iPhone with USB cable and trusted connection
- Dependencies:

```bash
sudo apt update
sudo apt install ifuse libimobiledevice6 libimobiledevice-utils fuse3 rsync exiftool


## Execution of script

Dry run
sudo ./iphone_backup.sh --dry-run

Full Backup & Cleanup
sudo ./iphone_backup.sh
