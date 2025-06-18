#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x

# TODO: Address below comments in next PR
# echo "Error: Please run this script with sudo!" >&2
# No need for sudo if running as root, since you already enforce it at the start. Remove sudo from commands inside functions.
working_dir=$(pwd)

# Usage info for user
usage() {
    echo "Usage: $0 <usb> <*.tar.gz> <*.sha256sum>"
    echo "Example: $0 /dev/sdc edge-readonly-3.0.20250528.2200-signed.raw.gz edge-readonly-3.0.20250528.2200-signed.raw.gz.sha256sum"
    exit 1
}

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run this script with sudo!"
    exit 1
fi

# Validate the inputs
if [ "$#" -ne 3 ]; then
    usage
fi

USB_DEVICE="$1"
USB_FILE1="$2"
USB_FILE2="$3"
OS_UPDATE_PART=1


# Validate USB device
if ! [[ "$USB_DEVICE" =~ ^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$ ]]; then
    echo "Error: '$USB_DEVICE' is NOT a valid USB/block device!"
    exit 1
fi

# Validate USB bootable files
#if [[ "$USB_FILES" != "usb-bootable-files.tar.gz" ]]; then
#    echo "Error: '$USB_FILES' is NOT a valid usb-bootable-files!"
#    exit 1
#fi

# Function to wipe filesystem signatures
wipe_partition() {
    # Check existing filesystem signatures
    echo "Checking existing filesystem signatures on "$USB_DEVICE"..."
    sudo wipefs --all --no-act "$USB_DEVICE"

    # Prompt user for confirmation
    read -p "Do you want to wipe all filesystem signatures from "$USB_DEVICE"? (yes/no): " user_input

    if [[ "$user_input" == "yes" ]]; then
        # Wipe filesystem signatures
        echo "Wiping filesystem signatures from "$USB_DEVICE"..."
        sudo wipefs --all "$USB_DEVICE" || {
            echo "Error: Failed to wipe filesystem signatures from $USB_DEVICE"
            exit 1
        }
        echo "Filesystem signatures wiped successfully."
    else
        echo "Operation canceled by user."
    fi
}

# Wait for the newly created partition for next operation from userspace
wait_for_partition() {
    device=$1
    while [ ! -b "$device" ]; do
        sleep 2
    done
}

# Extract USB bootable files
echo "Extracting USB bootable files..."
rm -rf usb_files && mkdir -p usb_files/update_images
cp "$USB_FILE1" usb_files/update_images
cp "$USB_FILE2" usb_files/update_images
cd usb_files/update_images || exit 1
cd "$working_dir" || exit 1

# Prepare USB device
echo "Preparing the USB bootable device..."
OS_IMG_PARTITION_SIZE="3000"

wipe_partition

# Check if blockdev is installed
if ! command -v blockdev &> /dev/null; then
    echo "Error: blockdev is not installed. Please install it before proceeding."
    exit 1
fi

# Check if partprobe is installed
if ! command -v partprobe &> /dev/null; then
    echo "Error: partprobe is not installed. Please install it before proceeding."
    exit 1
fi

sudo sgdisk -e "$USB_DEVICE" >/dev/null 2>&1
blockdev --rereadpt "${USB_DEVICE}"

# Create partitions
create_partition() {
    local start=$1
    local end=$2
    local label=$3
    sudo parted "$USB_DEVICE" --script mkpart primary ext4 "${start}" "${end}" >/dev/null 2>&1
    blockdev --rereadpt "$USB_DEVICE"
    sudo partprobe "$USB_DEVICE"
    local part_num
    part_num=$(sudo parted "$USB_DEVICE" -ms print 2>/dev/null | tail -n 1 | awk -F: '{print $1}')

    wait_for_partition "${USB_DEVICE}${part_num}"
    sleep 2

    mkfs.ext4 -F "${USB_DEVICE}${part_num}"
    echo "${label} partition created successfully."
}

echo "Creating OS Image partition,please wait !!!"
echo ""
create_partition "0" "${OS_IMG_PARTITION_SIZE}MB" "OS image storage"

# Copy files to partitions
copy_to_partition() {
    local part=$1
    local src=$2
    local dest=$3
    local retries=2
    local attempt=0

    while [ $attempt -lt $retries ]; do
        if sudo mount "${USB_DEVICE}${part}" /mnt && sudo cp "$src" "$dest"; then
            if sudo umount /mnt; then
                echo "Successfully copied $src to $dest on partition ${USB_DEVICE}${part}."
                break
            fi
        else
            echo "Error: Failed to copy $src to $dest on attempt $((attempt + 1))/$retries. Retrying..."
            sudo umount /mnt || true
            sleep 2
        fi
        attempt=$((attempt + 1))
        if [ "$attempt" -eq 2 ]; then
            echo "Error: Failed to copy $src to $dest after $retries attempts!"
            exit 1
        fi
    done
}
echo "Copying files to USB device..."
echo ""
echo "OS update image copying!!!"
os_filename=$(printf "%s\n" usb_files/update_images/*.raw.gz 2>/dev/null | head -n 1)
os_file_chsum=$(printf "%s\n" usb_files/update_images/*.raw.gz.sha256sum  2>/dev/null | head -n 1)
copy_to_partition "$OS_UPDATE_PART" "$os_filename" "/mnt"
copy_to_partition "$OS_UPDATE_PART" "$os_file_chsum" "/mnt"

#if copy_to_partition "$K8_PART" "usb_files/sen-k3s-package.tar.gz" "/mnt" && copy_to_partition "$K8_PART" "$CONFIG_FILE" "/mnt"; then
#    echo "USB bootable device is ready!"
#else
#    echo "USB Installation failed,please re-run the script again!!!"
#fi
