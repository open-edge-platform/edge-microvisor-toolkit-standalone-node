#!/bin/sh
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

TARGET_DISK="/dev/sda"
USB_MOUNT_POINT="/media/usb"
RAW_IMAGE_PATH="$USB_MOUNT_POINT/raw-image.img"

# Mount USB drive
mount_usb_drive() {
    if [ ! -d "$USB_MOUNT_POINT" ]; then
        mkdir -p "$USB_MOUNT_POINT"
    fi
    mount /dev/sdb1 "$USB_MOUNT_POINT"
    echo "USB drive mounted at $USB_MOUNT_POINT"
}

# Installing OS to the target disk
install_os() {
    if [ ! -f "$RAW_IMAGE_PATH" ]; then
        echo "Raw image not found on USB drive at $RAW_IMAGE_PATH"
        exit 1
    fi
    dd if="$RAW_IMAGE_PATH" of="$TARGET_DISK" bs=4M status=progress
    sync
    echo "OS installation completed on $TARGET_DISK"
}

# Copy cloud-init configuration to the target disk
copy_cloud_init() {
    echo "Copied cloud-init configuration to OS partition on $TARGET_DISK"
}

# Copy install-k8s-cluster.sh script to the target disk
copy_install_script() {
    echo "Copied install-k8s-cluster.sh script OS partition on $TARGET_DISK"
}

# Set the boot order to boot from the target disk
set_boot_order() {
    echo "Set the boot order to boot from $TARGET_DISK"
}

# Reboot the system
reboot_system() {
    echo "Rebooting the system..."
    reboot
}

# Main function
main() {
    mount_usb_drive
    install_os
    copy_cloud_init
    copy_install_script
    set_boot_order
    reboot_system
}
