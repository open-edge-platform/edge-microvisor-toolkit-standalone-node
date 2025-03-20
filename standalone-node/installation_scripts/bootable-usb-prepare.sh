#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x
source proxy_ssh_config

working_dir=$(pwd)
# Usage info for user 
usage() {
    
    echo "Usage: $0 <usb> <usb-bootable-files.tar.gz> <proxy_ssh_config>"
    echo "Example: $0 /dev/sda usb-bootable-files.tar.gz proxy_ssh_config"
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run this script with sudo!"
    exit 1
fi

# Validate the inputs
if [ "$#" -ne 3 ]; then
    usage
else
   if ! echo "$1" | grep -Eq '^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$'; then
       echo "Error: '$1' is NOT a valid USB/block device!"
       exit 1
   fi
   if ! echo "$2" | grep -Eq '^usb-bootable-files\.tar\.gz$'; then
       echo "Error: '$2' is NOT a valid usb-bootable-files!"
       exit 1
   fi

   if ! echo "$3" | grep -Eq '^proxy_ssh_config$'; then
       echo "Error: '$3' is NOT a valid proxy_ssh_config file!"
       exit 1
   fi

fi

# Check by mistake rootfs given as input for USB
rootfs=$(df / | awk 'NR==2 {print $1}')

if echo "$rootfs" |  grep -q "$1"; then
    echo "Looks like you are trying to install the bootable iso on rootfs of the disk $rootfs,Please check!!"
    exit 1
fi

# Check if proxy and SSH config files inputs provided or not.
if [  -z "$http_proxy" ] && [  -z "$https_proxy" ] && [  -z "$no_proxy" ] && [  -z "$HTTP_PROXY" ] &&  [  -z "$HTTPS_PROXY" ] &&  [  -z "$NO_PROXY" ]; then
   
    printf "No proxy settings updated under proxy_ssh_config file,do you want to continue (y/n)"
    read -r ANSWER
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
        echo "Looks proxy Settings not required,Proceeding for next steps"
    else
	exit 1
    fi
fi

# Check for the SSH Key
if [  -z "$ssh_key" ]; then
    echo "SSH Key is empty under proxy_ssh_config file,do you want to continue (y/n)"
    read -r ANSWER
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
        echo "NO SSH Key inputs provide,looks not required && proceeding for next steps!!"
    else
	exit 1
    fi
fi 

# Check at least http_proxy && https_prory (or) HTTP_PROXY && HTTPS_PROXY variables set
if { [ -n "$http_proxy" ] && [ -n "$https_proxy" ]; } || { [ -n "$HTTP_PROXY" ] && [ -n "$HTTPS_PROXY" ]; }; then
    echo ""
else
    echo "Please check. one of http_proxy && https_proxy or HTTP_PROXY && HTTPS_PROXY variable are not set in proxy_ssh_config file"
    exit 1
fi

echo "Untaring the usb-bootable-files.tar.gz file"
# Untar the usb-bootable-files.tar.gz and extract the files
if [ -d usb_files ]; then
    rm -rf usb_files
fi
mkdir -p usb_files

cp $2 usb_files

cd usb_files > /dev/null

tar -xzvf $2

if [ "$?" -eq 0 ]; then
    echo "USB bootable files extracted successfully!!"
else
    echo "Failure in USB bootable files extraction,please check!!!"
    exit 1
    cd "$working_dir"
fi
cd "$working_dir"

echo "Preparing the USB bootable device,please wait!!!"
# Variables
USB_DEVICE="$1"
ISO="usb_files/hook-os.iso"
OS_IMG_PARTITION_SIZE="3000"
OS_PART=5
K8_PART=6

# Clear the USB content before installation
sudo wipefs --all ${USB_DEVICE}

#sudo dd if=/dev/zero of=${USB_DEVICE} bs=100MB count=20

# Write the ISO to the USB drive
echo "Writing ISO to USB drive..."
sudo dd if=${ISO} of=${USB_DEVICE} bs=4M status=progress
sudo sync
sudo sgdisk -e ${USB_DEVICE} 
printf "fix\nq\n" | sudo parted ${USB_DEVICE} print > /dev/null 2>&1
# Create the new partitions for os image and cluster scripts

# Create OS storage partition
LAST_END=$(sudo parted ${USB_DEVICE} -ms print | tail -n 1 | awk -F: '{print $2}' | tr -d 'MB')
OS_IMG_PART_START=$(echo "$LAST_END + 1" | bc)
OS_IMG_PART_END=$(echo "$OS_IMG_PART_START + $OS_IMG_PARTITION_SIZE" | bc)

sudo parted "${USB_DEVICE}" --script mkpart primary ext4 ${OS_IMG_PART_START}MB ${OS_IMG_PART_END}MB > /dev/null 2>&1
blockdev --rereadpt  ${USB_DEVICE}
sudo partprobe ${USB_DEVICE}
sync
if [ $? -ne 0 ]; then
    echo "OS image storage partition creation failed!!!"
    exit 1
else
    echo "OS image storage partition Successfull"
fi
os_part_num=$(sudo parted ${USB_DEVICE} -ms print | tail -n 1 | awk -F: '{print $1}')
echo y | mkfs.ext4 ${USB_DEVICE}${os_part_num} > /dev/null

if [ $? -ne 0 ]; then
    echo "mkfs faild on /dev/$os_part_num!!!"
    exit 1
else
    echo "mkfs.ext4 success on /dev/$os_part_num"
fi


sudo partprobe ${USB_DEVICE}
sync

# Create K8 storage partition
LAST_END=$(sudo parted ${USB_DEVICE} -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB') > /dev/null 2>&1
K8_PART_START=$(echo "$LAST_END + 1" | bc)
K8_PART_END="100%"

sudo parted "${USB_DEVICE}" --script mkpart primary ext4 ${LAST_END}MB ${K8_PART_END}
if [ $? -ne 0 ]; then
    echo "K8 storage partition creation failed!!!"
    exit 1
else
    echo "K8 storage partition Successfull"
fi

blockdev --rereadpt  ${USB_DEVICE}
sudo partprobe ${USB_DEVICE}
sync
k8_part_num=$(sudo parted ${USB_DEVICE} -ms print | tail -n 1 | awk -F: '{print $1}')
echo y | mkfs.ext4 ${USB_DEVICE}${k8_part_num} > /dev/null

if [ $? -ne 0 ]; then
    echo "mkfs faild on /dev/$k8_part_num!!!"
    exit 1
else
    echo "mkfs.ext4 success on /dev/$k8_part_num"
fi

sudo partprobe ${USB_DEVICE}
sync

echo "Copying the OS image to USB device,please wait!!"
# Copy the OS and K8* scripts to USB device
sudo mount "${USB_DEVICE}${OS_PART}" /mnt
sudo cp usb_files/*.raw.gz  /mnt
if [ $? -ne 0 ]; then
    echo "tiber microvisor image not copied to USB,please check!!!"
    exit 1
fi
sudo umount /mnt

echo "Copying the K8 Scripts to USB device,please wait!!!"

sudo mount "${USB_DEVICE}${K8_PART}" /mnt
sudo cp usb_files/sen-rke2-package.tar.gz /mnt

if [ $? -ne 0 ]; then
    echo "k8-scripts not copied to USB,please check!!!"
    exit 1
fi
sudo cp proxy_ssh_config /mnt

if [ $? -ne 0 ]; then
    echo "proxy_ssh_config file not copied to USB,please check!!!"
    exit 1
fi

sudo umount /mnt
sync

echo "USB bootable device ready!!!"


