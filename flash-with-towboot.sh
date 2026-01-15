#!/bin/bash
set -euo pipefail

# Flash NixOS + Tow-Boot to SD card for Odroid C4
# Usage: ./flash-with-towboot.sh <node-image.img.zst> <disk>
# Example: ./flash-with-towboot.sh ~/odroid-images/nixos-node1.img.zst /dev/disk8

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOWBOOT="${SCRIPT_DIR}/odroid-C4-2023.07-007/shared.disk-image.img"

usage() {
    echo "Usage: $0 <image.img.zst> [disk]"
    echo
    echo "  image.img.zst  Path to the compressed NixOS SD image"
    echo "  disk           Target disk (e.g., /dev/disk8)"
    echo
    echo "If disk is not provided, will list available disks."
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

IMAGE_ZST="$1"
DISK="${2:-}"

# Verify Tow-Boot exists
if [[ ! -f "$TOWBOOT" ]]; then
    echo "ERROR: Tow-Boot image not found at $TOWBOOT"
    echo "Run: cd $SCRIPT_DIR && curl -LO https://github.com/Tow-Boot/Tow-Boot/releases/download/release-2023.07-007/odroid-C4-2023.07-007.tar.xz && tar -xvf odroid-C4-2023.07-007.tar.xz"
    exit 1
fi

# Verify image exists
if [[ ! -f "$IMAGE_ZST" ]]; then
    echo "ERROR: Image file not found: $IMAGE_ZST"
    exit 1
fi

# List disks if no disk specified
if [[ -z "$DISK" ]]; then
    echo "Available external disks:"
    echo
    diskutil list external
    echo
    read -p "Enter the disk to flash (e.g., /dev/disk8): " DISK
fi

# Safety checks
if [[ "$DISK" == "/dev/disk0" ]] || [[ "$DISK" == "/dev/disk1" ]] || [[ "$DISK" == "/dev/disk3" ]]; then
    echo "ERROR: Refusing to write to internal disk!"
    exit 1
fi

if [[ ! -e "$DISK" ]]; then
    echo "ERROR: Disk $DISK does not exist"
    exit 1
fi

# Confirm
echo
echo "=== SD Card Flash Summary ==="
echo "NixOS Image: $IMAGE_ZST"
echo "Tow-Boot:    $TOWBOOT"
echo "Target Disk: $DISK"
echo
echo "WARNING: This will ERASE all data on $DISK"
read -p "Type 'yes' to continue: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Unmount disk
echo
echo "Unmounting $DISK..."
diskutil unmountDisk "$DISK" || true

# Create temp file for decompressed image
TEMP_IMG=$(mktemp /tmp/nixos-XXXXXX.img)
trap "rm -f $TEMP_IMG" EXIT

# Decompress
echo "Decompressing NixOS image (this may take a minute)..."
zstd -d "$IMAGE_ZST" -o "$TEMP_IMG"

# Flash NixOS image
RAW_DISK="${DISK/disk/rdisk}"
echo "Writing NixOS image to $RAW_DISK..."
sudo dd if="$TEMP_IMG" of="$RAW_DISK" bs=4m status=progress

# Write Tow-Boot bootloader to the beginning of the disk
# The shared.disk-image.img contains the bootloader starting at sector 1
# We skip sector 0 (MBR) and write from sector 1 onwards
echo "Writing Tow-Boot bootloader..."
sudo dd if="$TOWBOOT" of="$RAW_DISK" bs=512 skip=1 seek=1 conv=notrunc

# Sync
echo "Syncing..."
sync

# Eject
echo "Ejecting..."
diskutil eject "$DISK"

echo
echo "=== Success! ==="
echo "SD card is ready. Label it and insert into your Odroid C4."
echo "After powering on, wait 2-3 minutes, then try:"
echo "  ssh admin@<hostname>.local"
