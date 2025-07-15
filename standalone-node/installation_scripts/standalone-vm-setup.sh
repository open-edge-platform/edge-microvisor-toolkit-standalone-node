#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#########################################################################
#
# This script to setup the EMT-S on virtual edge node.
# It will speed up the developer PR verification and real h/w limitations
#
#########################################################################
set -e

new_img=""

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run this script with sudo!"
    exit 1
fi

# Check if the is virtual edge node or not
CONFIG_FILE=config-file
deploy_mode=$(grep '^deploy_envmt=' "$CONFIG_FILE" | cut -d '=' -f2)
deploy_mode=$(echo "$deploy_mode" | tr -d '"')

if [ "$deploy_mode" != "ven" ]; then
    echo "Please Make sure update the deploy_envmt="ven" in config-file"
    exit 1
fi

# if Custom image update
if [ -n "$1" ]; then
    if echo "$1" | grep -qE '\.gz$'; then
        new_img=$1
    else
        echo "Error: EMT image is not a .gz file"
        exit 1
    fi
fi
# Install qemu-system 
if ! dpkg -s qemu-system-x86 >/dev/null 2>&1; then
    echo  "Installing qemu-system-x86.., Please Wait!!"
    apt update
    apt install -y qemu-system-x86 >/dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echo "Qemu Installation Failed,Please check!!"
        exit 1
    fi	
else
    echo  "Qemu already installed Skipping it"

fi

if ! dpkg -s net-tools >/dev/null 2>&1; then
   apt install net-tools -y
fi

pub_interface_name=$(route | grep '^default' | grep -o '[^ ]*$')
host_ip=$(ifconfig "${pub_interface_name}" | grep 'inet ' | awk '{print $2}')


# Create the vitrual usb disk
if [ -e usb-disk ]; then
    rm -rf usb-disk
fi
qemu-img create -f qcow2 usb-disk 64G > /dev/null 2>&1 || { echo "virtual usb device failed to create,please check"; exit 1; } 

echo "virtual-usb of size 64GB created successfully"

# Bind/Mount the virtual usb disk to qemu network block device
# Number of partitions on the virtual disk
modprobe nbd max_part=8

if [ ! -e /sys/block/nbd0/pid ]; then
    echo "Connecting usb-disk..."
    qemu-nbd --connect=/dev/nbd0 usb-disk
fi

# Prepare the USB bootable device. /dev/nbd0 is the virtual usb device.

./bootable-usb-prepare.sh /dev/nbd0 usb-bootable-files.tar.gz config-file || { echo "USB device setup failed,please check"; exit 1; }

# Copy the new image if its provided
if [ ! -z "$new_img" ]; then
    mount /dev/nbd0p5 /mnt
    rm -rf /mnt/*
    cp $new_img /mnt
    cp "$new_img" /mnt
    umount /mnt
    sync
fi

# Launch the VM for EMT-S installation
# Create the emt-disk.img for installation

if [ -e emt-disk.img ]; then
    rm -rf emt-disk.img
fi
qemu-img create -f qcow2 emt-disk.img 64G > /dev/null 2>&1 || { echo "creating emt disk image failed to create,please check"; exit 1; }

echo "Starting the Installation"
echo ""
echo "Please see the installation status on VNC viewer.Enter $host_ip:1 on vnc viewer"
# Added -cpu host,+vms It will support nested VM configuration as well
sudo -E qemu-system-x86_64  \
  -m 4G   -enable-kvm  \
  -cpu host,+vmx \
  -machine q35,accel=kvm \
  -bios /usr/share/qemu/OVMF.fd  \
  -vnc :1 \
  -drive file=emt-disk.img,format=qcow2 \
  -device usb-ehci,id=ehci  \
  -device usb-storage,bus=ehci.0,drive=usb,removable=on  \
  -drive file=/dev/nbd0,format=raw,id=usb,if=none \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0
  
if [ "$?" -ne 0 ]; then
    echo "Intallation VM launch Failed,Please check!!"
fi

trap 'killall --quiet standalone-vm-launch.sh || true' EXIT 
