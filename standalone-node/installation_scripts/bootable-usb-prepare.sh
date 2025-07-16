#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x
# shellcheck source=installation_scripts/config-file
source config-file > /dev/null 2>&1 

#### Global variables
# Color codes ####### 

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'
YELLOW='\033[0;33m'

#####################

ISO="usb_files/emt-uos.iso"
OS_IMG_PARTITION_SIZE="3000"
K8S_PARTITION_SIZE="6000"
GUEST_VM_SIZE="100%"
OS_PART=5
K8_PART=6
USER_APPS_PART=7
BAR_WIDTH=50        
TOTAL_USB_PREPARATION_STEPS=8 
USB_PREPARE_STEP=0
LOG_FILE="bootable_usb_setup_log.txt"
MAX_STATUS_MESSAGE_LENGTH=28

: >"$LOG_FILE"

working_dir=$(pwd)

# Usage info for user
usage() {
    echo "Usage: $0 <usb> <usb-bootable-files.tar.gz> <config-file>"
    echo "Example: $0 /dev/sda usb-bootable-files.tar.gz config-file"
    exit 1
}

check_mnt_mount_exist() {
    mounted=$(lsblk -o MOUNTPOINT | grep "/mnt")
    if [ -n "$mounted" ]; then
        umount -l /mnt
    fi
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
if ! [[ "$USB_DEVICE" =~ ^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|nbd[0-9]+)$ ]]; then
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

if [ -z "$user_name" ]; then
    echo "User_name not provided,please provide valid User_name config-file"
    exit 1
fi

if [ -z "$host_type" ] || { [ "$host_type" != "kubernetes" ] && [ "$host_type" != "container" ]; }; then
    echo "Invalid host_type => $host_type provided, Please check!. It should not be empty or host_type=kubernetes/container"
    exit 1
fi

# Ask the password from cmd line 
echo -n "Please Set the Password for $user_name: "
stty -echo
read -r password
stty echo
echo 

# Store the password in hidden file and delete onces it copied to USB
echo "passwd=$password" > "$(pwd)/.psswd"
chmod 600 "$(pwd)/.psswd"

# Validate the custom-cloud-init section
if ! dpkg -s python3 > /dev/null 2>&1; then
    if ! apt install -y python3 > /dev/null 2>&1; then
        echo "Pyhon installation failed,please check!!"
    fi
fi
CONFIG_FILE="config-file"
START_MARKER="^services:"

# Extract YAML content from custom cloud-init-section
# if any error,throw the errors  
YAML_CONTENT=$(awk "/$START_MARKER/ {found=1} found" "$CONFIG_FILE")

# Validate using Python
echo "$YAML_CONTENT" | python3 -c '
import sys, yaml

try:
    data = yaml.safe_load(sys.stdin.read())
    # Validate runcmd
    if "runcmd" in data:
        runcmd = data["runcmd"]
        if runcmd is None:
            print("")
        elif not isinstance(runcmd, list):
            sys.exit(1)
        else:
            for item in runcmd:
                if not isinstance(item, str) and not isinstance(item, list):
                    print(f"Invalid runcmd item: {item!r}")
                    sys.exit(1)
    else:
        print("")
except yaml.YAMLError as e:
    print("Custom cloud-init YAML is invalid:\n", e)
    sys.exit(1)
'
# Catch the Error
# shellcheck disable=SC2181
if [ "$?" -ne 0 ]; then
    echo "Custom cloud-init file is not valid,Please check!!"
    exit 1
fi

# --- Progress Bar Function ---
show_progress_bar() {
    progress=$1 
    message=$2 

    # Calculate percentage
    percentage=$(( (progress * 100) / TOTAL_USB_PREPARATION_STEPS ))

    # Calculate number of green and red characters
    green_chars=$(( (progress * BAR_WIDTH) / TOTAL_USB_PREPARATION_STEPS ))
    red_chars=$(( BAR_WIDTH - green_chars-1 ))
    padded_status_message=$(printf "%-*s" "$MAX_STATUS_MESSAGE_LENGTH" "$message")

    # Print the Installation Progressbar
    printf "\r\033[K"
    printf "\r${YELLOW}%s${NC} [" "$padded_status_message"
    printf "${GREEN}%0.s#" $(seq 1 $green_chars)
    printf "${RED}%0.s-" $(seq 1 $red_chars)
    printf "${NC}] %3d%%" "$percentage"
}

# Prepare the USB setup 
prepare_usb_setup() {
    # Extract USB bootable files
    echo "Extracting USB bootable files..."
    rm -rf usb_files && mkdir -p usb_files
    cp "$USB_FILES" usb_files
    cd usb_files || exit 1
    tar -xzvf "$USB_FILES" || {
        echo "Error: Failed to extract USB bootable files!"
        return 1 
    }
    cd "$working_dir" || return 1 
    # Verify MD5 checksum of required files
    echo "Verifying MD5 checksum of required files..."
    checksum_file="usb_files/checksums.md5"
    if [ -f "$checksum_file" ]; then
        pushd usb_files >/dev/null || exit
        for file in emt-uos.iso edge_microvisor_toolkit.raw.gz; do
            if [ -f "$file" ]; then
                calculated_md5=$(md5sum "$file" | awk '{print $1}')
                expected_md5=$(grep "$file" checksums.md5 | awk '{print $1}')
                if [ "$calculated_md5" != "$expected_md5" ]; then
                    echo "Error: MD5 checksum mismatch for $file!"
		    return 1 
                else
                    echo "MD5 checksum verified for $file."
                fi
            else
                echo "Error: $file not found!"
		return 1
            fi
        done
        popd >/dev/null || exit
    else
        echo "Error: Checksum file $checksum_file not found!"
	return 1
    fi
    return 0
}

# Wipeoff the USB before install 
wipe_disk() {
    echo "Wipe of the disk"
    check_mnt_mount_exist
    sudo wipefs --all "$USB_DEVICE" || return 1
}

# Flash iso to USB
flash_iso() {
    echo "Write the ISO to USB"
    if sudo dd if="$ISO" of="$USB_DEVICE" bs=4M status=progress && sudo sync; then
        sudo sgdisk -e "$USB_DEVICE" >/dev/null 2>&1
        blockdev --rereadpt "${USB_DEVICE}"
	return 0
    else
    	return 1
    fi
}

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

    if [[ $USB_DEVICE == /dev/nbd* ]]; then
        part_num="p$part_num"
    fi
    wait_for_partition "${USB_DEVICE}${part_num}"
    sleep 2

    echo y | mkfs.ext4 "${USB_DEVICE}${part_num}" >/dev/null || {
        echo "Error: mkfs failed on ${USB_DEVICE}${part_num}!"
        return 1 
    }
    echo "${label} partition created successfully."
    return 0
}

partitions_setup() {
    # Calculate the start and end points for partitions
    LAST_END=$(sudo parted "$USB_DEVICE" -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB')
    if [ -z "$LAST_END" ]; then
        echo "Error: Failed to determine the last partition end point!"
        return 1 
    fi

    echo "Creating OS Image,K8 Storage partitions,please wait !!!"
    echo ""
    START_MB="${LAST_END//MB/}"
    END_MB=$(echo "$START_MB + $OS_IMG_PARTITION_SIZE" | bc)
    create_partition "${START_MB}MB" "${END_MB}MB" "OS image storage" || return 1
    create_partition "$(sudo parted "$USB_DEVICE" -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB')MB" "${K8S_PARTITION_SIZE}" "K8 storage" || return 1
    create_partition "$(sudo parted "$USB_DEVICE" -ms print | tail -n 1 | awk -F: '{print $3}' | tr -d 'MB')MB" "${GUEST_VM_SIZE}" "Guest VM storage" || return 1

}

# Copy files to partitions
copy_to_partition() {
    local part=$1
    local src=$2
    local dest=$3
    local retries=2
    local attempt=0

    if [[ $USB_DEVICE == /dev/nbd* ]]; then
        part="p$part"
    fi
    while [ $attempt -lt $retries ]; do
	check_mnt_mount_exist
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
            return 1 
        fi
    done
}

copy_files() {
    echo "Copying files to USB device..."
    echo ""
    echo "OS image copying!!!"
    os_filename=$(printf "%s\n" usb_files/*.raw.gz 2>/dev/null | head -n 1)
    copy_to_partition "$OS_PART" "$os_filename" "/mnt"
    echo ""
    echo "Custom files copying!!!"

    if copy_to_partition "$K8_PART" "$CONFIG_FILE" "/mnt" && copy_to_partition "$K8_PART" "$(pwd)/.psswd" "/mnt";then
        echo "Custom files copied!"
    fi
    # Remove the hidden password file
    rm -rf "$(pwd)/.psswd"
}
copy_user_apps() {
    echo "Copying user-apps to USB device..."
    if find user-apps -mindepth 1 ! -name 'readme.md' | grep -q .; then

        if [[ $USB_DEVICE == /dev/nbd* ]]; then
            USER_APPS_PART="p$USER_APPS_PART"
        fi
        check_mnt_mount_exist
        mount "${USB_DEVICE}${USER_APPS_PART}" /mnt
        # Use rsync for fater copr
        if dpkg -s rsync; then
            if rsync -ah --inplace user-apps /mnt/; then 
                echo "user-apps data copied successfully"
            else
                echo "user-apps data fails to copy please check!!"
                umount /mnt
                exit 1
            fi
        else             
            if cp -r user-apps /mnt; then
                echo "user-apps data copied successfully"
            else
                echo "user-apps data fails to copy please check!!"
                umount /mnt
                exit 1
            fi
        fi
        umount /mnt
        sync
    fi
}

main() {

    # Step 1: Prepare the USB setup with required files and checksum
    USB_PREPARE_STEP=0
    show_progress_bar "$USB_PREPARE_STEP" "Preparing USB Setup,please wait"
    if ! prepare_usb_setup  >> "$LOG_FILE" 2>&1; then 
        echo -e "${RED}\nERROR: Preparing USB Setup Failed. Aborting.${NC}"
        exit 1
    fi
    USB_PREPARE_STEP=$((USB_PREPARE_STEP+1))
    show_progress_bar "$USB_PREPARE_STEP" "Preparing USB Setup Done"

    # Step 2: Wipe off the USB disk before install 
    USB_PREPARE_STEP=2
    show_progress_bar "$USB_PREPARE_STEP" "Wipeoff the USB device "
    if ! wipe_disk  >> "$LOG_FILE" 2>&1; then 
        echo -e "${RED}\nERROR: Wipeoff USB device faild. Aborting.${NC}"
        exit 1
    fi

    # Step 3: Flash the ISO to USB 
    USB_PREPARE_STEP=3
    show_progress_bar "$USB_PREPARE_STEP" "Flashing ISO Image to USB"
    if ! flash_iso  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nWARNING: Flashing ISO image failed, but main process completed.${NC}"
    fi

    # Step 4: Create the USB partitions for storing OS && K8S scripst 
    USB_PREPARE_STEP=4
    show_progress_bar "$USB_PREPARE_STEP" "Creating USB Partitions"
        if ! partitions_setup  >> "$LOG_FILE" 2>&1; then 
        echo -e "${RED}\nWARNING: Creating USB failed, but main process completed.${NC}"
    fi

    # Step 5: Copy the OS && K8S files to USB 
    USB_PREPARE_STEP=5
    show_progress_bar "$USB_PREPARE_STEP" "Copying OS,Custom files to USB"
    if ! copy_files  >> "$LOG_FILE" 2>&1; then 
        echo -e "${RED}\nWARNING: Copying files to USB failed, but main process completed.${NC}"
    fi

    # Step 5: Copy user-apps to USB
    USB_PREPARE_STEP=6
    show_progress_bar "$USB_PREPARE_STEP" "Copying user-apps to USB"
    if ! copy_user_apps  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nWARNING: Copying user-apps to USB failed, but main process completed.${NC}"
    fi

    # Step 6: sync the USB device 
    USB_PREPARE_STEP=7
    show_progress_bar "$USB_PREPARE_STEP" ""
    sync

    # Final bar completion and message
    show_progress_bar "$TOTAL_USB_PREPARATION_STEPS" "Complete!"

}
#####@main
echo -e "${BLUE}Started the Bootable USB creation, it will take a few minutes. Please wait!!!${NC}" 
main
echo -e "\n"
echo -e "\n${BLUE}Bootable USB Device is ready!!${NC}"
