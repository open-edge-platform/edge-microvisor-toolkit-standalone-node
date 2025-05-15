#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x
# shellcheck source=installation_scripts/config-file
source config-file

working_dir=$(pwd)

# Usage info for user
usage() {
    echo "Usage: $0 <usb> <usb-bootable-files.tar.gz> <config-file>"
    echo "Example: $0 /dev/sda usb-bootable-files.tar.gz config-file"
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
USB_FILES="$2"
CONFIG_FILE="$3"

# Validate USB device
if ! [[ "$USB_DEVICE" =~ ^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$ ]]; then
    echo "Error: '$USB_DEVICE' is NOT a valid USB/block device!"
    exit 1
fi

# Validate USB bootable files
if [[ "$USB_FILES" != "usb-bootable-files.tar.gz" ]]; then
    echo "Error: '$USB_FILES' is NOT a valid usb-bootable-files!"
    exit 1
fi

# Validate proxy SSH config file
if [[ "$CONFIG_FILE" != "config-file" ]]; then
    echo "Error: '$CONFIG_FILE' is NOT a valid proxy_ssh_config file!"
    exit 1
fi

# Check if rootfs is mistakenly given as USB input
rootfs=$(df / | awk 'NR==2 {print $1}')
if [[ "$rootfs" == "$USB_DEVICE" ]] || echo "$rootfs" | grep -q "$1"; then
    echo "Error: You are trying to install the bootable ISO on the root filesystem of the disk '$rootfs'. Please check!"
    exit 1
fi

# Check proxy,ssh_key && credentails
if [ -z "$http_proxy" ] && [ -z "$https_proxy" ] && [ -z "$no_proxy" ] && [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ] && [ -z "$NO_PROXY" ]; then
    read -rp "No proxy settings found. Do you want to continue? (y/n): " ANSWER
    [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]] && exit 1
fi

if [ -z "$ssh_key" ]; then
    read -rp "SSH Key is empty. Do you want to continue? (y/n): " ANSWER
    [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]] && exit 1
fi

if [ -z "$user_name" ] || [ -z "$passwd" ]; then
    echo "User_name/Password credentials not provided,please provide valid User_name and Password under config-file"
    exit 1
fi


# Extract USB bootable files
echo "Extracting USB bootable files..."
rm -rf usb_files && mkdir -p usb_files
cp "$USB_FILES" usb_files
cd usb_files || exit 1
tar -xzvf "$USB_FILES" || {
    echo "Error: Failed to extract USB bootable files!"
    exit 1
}
cd "$working_dir" || exit 1

# Verify MD5 checksum of required files
echo "Verifying MD5 checksum of required files..."
checksum_file="usb_files/checksums.md5"
if [ -f "$checksum_file" ]; then
    pushd usb_files >/dev/null || exit
    for file in hook-os.iso edge_microvisor_toolkit.raw.gz sen-rke2-package.tar.gz; do
        if [ -f "$file" ]; then
            calculated_md5=$(md5sum "$file" | awk '{print $1}')
            expected_md5=$(grep "$file" checksums.md5 | awk '{print $1}')
            if [ "$calculated_md5" != "$expected_md5" ]; then
                echo "Error: MD5 checksum mismatch for $file!"
                exit 1
            else
                echo "MD5 checksum verified for $file."
            fi
        else
            echo "Error: $file not found!"
            exit 1
        fi
    done
    popd >/dev/null || exit
else
    echo "Error: Checksum file $checksum_file not found!"
    exit 1
fi

# Prepare USB device
echo "Preparing the USB bootable device..."
ISO="usb_files/hook-os.iso"
OS_IMG_PARTITION_SIZE="3000"
K8S_PARTITION_SIZE="8000"
OS_PART=5
K8_PART=6

echo "Wipe of the disk"
sudo wipefs --all "$USB_DEVICE"

echo "Write the ISO to USB"

sudo dd if="$ISO" of="$USB_DEVICE" bs=4M status=progress && sudo sync
sudo sgdisk -e "$USB_DEVICE" >/dev/null 2>&1
blockdev --rereadpt "${USB_DEVICE}"
printf "fix\nq\n" | sudo parted "$USB_DEVICE" print >/dev/null 2>&1

# Wait for the newly created partition for next operation from userspace
wait_for_partition() {
    device=$1
    while [ ! -b "$device" ]; do
        sleep 2
    done
}

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

    echo y | mkfs.ext4 "${USB_DEVICE}${part_num}" >/dev/null || {
        echo "Error: mkfs failed on ${USB_DEVICE}${part_num}!"
        exit 1
    }
    echo "${label} partition created successfully."
}

# Calculate the start and end points for partitions
LAST_END=$(sudo parted "$USB_DEVICE" -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB')
if [ -z "$LAST_END" ]; then
    echo "Error: Failed to determine the last partition end point!"
    exit 1
fi

echo "Creating OS Image,K8 Storage partitions,please wait !!!"
echo ""
create_partition "${LAST_END}" "$(echo "${LAST_END} + ${OS_IMG_PARTITION_SIZE}" | bc)MB" "OS image storage"
create_partition "$(sudo parted "$USB_DEVICE" -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB')MB" "${K8S_PARTITION_SIZE}" "K8 storage"

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
echo "OS image copying!!!"
os_filename=$(printf "%s\n" usb_files/*.raw.gz 2>/dev/null | head -n 1)
copy_to_partition "$OS_PART" "$os_filename" "/mnt"
echo ""
echo "K8-Cluster scripts copying!!!"

if copy_to_partition "$K8_PART" "usb_files/sen-rke2-package.tar.gz" "/mnt" && copy_to_partition "$K8_PART" "$CONFIG_FILE" "/mnt"; then
    echo "USB bootable device is ready!"
else
    echo "USB Installation failed,please re-run the script again!!!"
fi

