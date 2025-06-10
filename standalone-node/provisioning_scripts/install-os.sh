#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x

### Global Variables ###
usb_disk=""
usb_devices=""
# shellcheck disable=SC2034
usb_count=""
blk_devices=""
os_disk=""
os_part=5
k8_part=6
os_rootfs_part=2
os_data_part=3
LOG_FILE="/var/log/os-installer.log"
#########################

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'
YELLOW='\033[0;33m'

BAR_WIDTH=50
TOTAL_PROVISION_STEPS=8
PROVISION_STEP=0
MAX_STATUS_MESSAGE_LENGTH=25

>$LOG_FILE

# Dump the failure logs to USB for debugging
dump_logs_to_usb() {
    # Mount the USB
    mount "${usb_disk}${k8_part}" /mnt
    cp /var/log/os-installer.log /mnt
    umount /mnt
}

success() {
    echo -e "${GREEN}$1${NC}" 
}

failure() {
    echo ""
    echo -e "\n${RED}$1${NC}" 
    dump_logs_to_usb
    echo -e "\n${RED}Exit the Installation. Please check /var/log/os-installer.log file for more details.${NC}" 
}

# Check if mnt is already mounted,if yes unmount it
check_mnt_mount_exist() {
    mounted=$(lsblk -o MOUNTPOINT | grep "/mnt")
    if [ -n "$mounted" ]; then
        umount -l /mnt
    fi
}

# Wait for a few seconds for USB emulation as hook OS boots fast
detect_usb() {
    for _ in {1..15}; do
        usb_devices=$(lsblk -dn -o NAME,TYPE,SIZE,RM | awk '$2 == "disk" && $4 == 1 && $3 != "0B" {print $1}')
        for disk_name in $usb_devices; do
            # Bootable USB has 6 partitions,ignore other disks
            if [ "$(lsblk -l "/dev/$disk_name" | grep -c "^$(basename "/dev/$disk_name")[0-9]")" -eq 6 ]; then
                usb_disk="/dev/$disk_name"
                echo "$usb_disk"
                return
            fi
        done
        sleep 1
    done
}

# Get the USB disk where the OS image and K8* scripts are copied
get_usb_details() {
    echo -e "${BLUE}Get the USB details!!${NC} [1/9]" 
    # Check if the USB is detected at Hook OS
    usb_disk=$(detect_usb)

    # Exit if no USB device found
    if [ -z "$usb_disk" ]; then
        failure "No valid USB device found, exiting the installation."
        return 1 
    fi
    success "Found the USB Device $usb_disk"

    # Check partition 5 and 6 for OS and K8 Scripts data, if not exit the installation
    #check_mnt_mount_exist
    mount -o ro "${usb_disk}${os_part}" /mnt
    if ! ls /mnt/*.raw.gz >/dev/null 2>&1; then
        failure "OS Image File not Found, exiting the installation."
        umount /mnt
        return 1 
    else
        umount /mnt
    fi
    #check_mnt_mount_exist
    mount -o ro "${usb_disk}${k8_part}" /mnt
    if ! ls /mnt/sen*.tar.gz >/dev/null 2>&1; then
        failure "K8* Script File not Found, exiting the installation."
        umount /mnt
        return 1 
    else
        if ! ls /mnt/config-file >/dev/null 2>&1; then
            failure "Configuration file not Found, exiting the installation."
            umount /mnt
            return 1 
        fi
        umount /mnt
    fi

    return 0
}

# Get the list of block devices on the device and choose the best disk for installation
get_block_device_details() {
    echo -e "${BLUE}Get the block device for OS installation${NC} [2/9]" 

    # List of block devices attached to the system, ignore USB and loopback devices
    blk_devices=$(lsblk -o NAME,TYPE,SIZE,RM | grep -i disk | awk '$1 ~ /sd*|nvme*/ {if ($3 !="0B" && $4 ==0) {print $1}}')
    blk_dev_count=$(echo "$blk_devices" | wc -l)

    if [ -z "$blk_dev_count" ]; then
        failure "No valid hard disk found for installation, exiting the installation!!"
        return 1 
    fi

    # If only one disk found, use that for installation
    if [ "$blk_dev_count" -eq 1 ]; then
        os_disk="/dev/$blk_devices"
    else
        # If more than one block disk found, choose the disk with the smallest size
        # NVME is preferred as Rank1 compared to SATA
        min_size_disk=$(lsblk -dn -o NAME,SIZE,RM,TYPE | awk '$3 == 0 && $4 == "disk" && $2 !="0B" {print $1, $2}' | sort -hk2,2 -k1,1 | awk 'NR==1 {min=$2} $2 == min {print "/dev/" $1; exit}')
        os_disk="$min_size_disk"
    fi
    echo -e "${GREEN}Found the OS disk  $os_disk${NC}" 

    # Clear the disk partitions
    for disk_name in ${blk_devices}; do
        dd if=/dev/zero of="/dev/$disk_name" bs=500M count=20
    done
    echo "success to find the disk"
    return 0
}

# Install the OS image
install_os_on_disk() {
    if echo "$os_disk" | grep -q "nvme"; then
        os_rootfs_part="p$os_rootfs_part"
        os_data_part="p$os_data_part"
    fi
    check_mnt_mount_exist
    mount "$usb_disk${os_part}" /mnt
    os_file=$(find /mnt -type f -name "*.raw.gz" | head -n 1)

    if [ -n "$os_file" ]; then
        # Install the OS image on the Disk
        echo -e "${BLUE}Installing $os_file on disk $os_disk!!${NC} [3/9]"
        dd if=/dev/zero of="$os_disk" bs=1M count=500

        # Check if the OS image flash was successful
        if gzip -dc "$os_file" | dd of="$os_disk" bs=4M && sync; then
            success "Successfully Installed OS on the Disk $os_disk"
            umount /mnt
            partprobe "$os_disk" && sync
            blockdev --rereadpt "$os_disk"
            sleep 5
        else
            failure "Failed to Install OS on the Disk $os_disk, please check!!"
            umount /mnt
            return 1
        fi
    else
        failure "OS image file not found in the USB, please check!!"
        umount /mnt
        return 1
    fi
    return 0
}

# Create the USER for the target OS
create_user() {

    # Copy the config-file from usb device to disk
    mkdir -p /mnt1
    mount -o ro "${usb_disk}${k8_part}" /mnt1

    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    cp /mnt1/config-file /mnt/etc/cloud/

    umount /mnt1
    rm -rf /mnt1

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)
    passwd=$(grep '^passwd=' "$CONFIG_FILE" | cut -d '=' -f2)

    echo -e "${BLUE}Creating the User Account!!${NC} [5/9]" 
    # Mount all required partitions and do chroot to OS
    chroot /mnt /bin/bash <<EOT
set -e

# Create the user as $user_name and add to sudo and don't ask password while sudo

useradd -m -s /bin/bash $user_name && echo "$user_name:$passwd" | chpasswd && echo '$user_name ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$user_name

EOT
    # shellcheck disable=SC2181
    if [ "$?" -eq 0 ]; then
        success "Successfully created the user"
        umount /mnt
    else
        failure "Failed to create the user!!!"
        umount /mnt
        return 1 
    fi
    return 0
}

# Install cloud-init file on OS
install_cloud_init_file() {

    # Copy the cloud init file from Hook OS to target OS
    echo -e "${BLUE}Installing the Cloud-init file!!${NC} [4/9]" 

    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    if cp /etc/scripts/cloud-init.yaml /mnt/etc/cloud/cloud.cfg.d/installer.cfg && chmod +x /mnt/etc/cloud/cloud.cfg.d/installer.cfg; then
        success "Successfuly copied the cloud-init file"
    else
        failure "Fail to copy the cloud-init file,please check!!!"
        umount /mnt
        return 1 
    fi

    # Create the cloud-init Dsi identity
    chroot /mnt /bin/bash <<EOT
touch /etc/cloud/ds-identify.cfg 
echo "datasource: NoCloud" > /etc/cloud/ds-identify.cfg
chmod 600 /etc/cloud/ds-identify.cfg

# Update the proxy settings to yes /etc/profile.d
sed -i 's/PROXY_ENABLED="no"/PROXY_ENABLED="yes"/g' /etc/sysconfig/proxy
EOT

    # Copy Edge node logs collection script
    cp /etc/scripts/collect-logs.sh /mnt/etc/cloud/
    cp /etc/scripts/rke2-setup-post-reboot.sh /mnt/etc/cloud/
    umount /mnt
    return 0
}

# Install K8* script to OS disk under /opt
install_k8_script() {
    echo -e "${BLUE}Copying the K8 Cluster Scripts!!${NC} [8/9]" 
    # Copy the scripts from USB disk to /opt on the disk
    mkdir -p /mnt2
    mount -o ro "${usb_disk}${k8_part}" /mnt2

    # Mount the OS disk
    check_mnt_mount_exist

    if mount "$os_disk$os_data_part" /mnt && cp /mnt2/sen-rke2-package.tar.gz /mnt/; then
        success "Successfuly copied the K8 scripts to /opt on the disk"
    else
        failure "Fail to copy the K8 scripts to /opt on the disk,please check!!!"
        return 1 
    fi
    umount /mnt2
    umount /mnt
    rm -rf /mnt2
    return 0
}

# Update the Proxy settings under /etc/environment
setup_proxy_settings() {
    echo -e "${BLUE}Set the Proxy Settings!!${NC} [6/9]"

    mount -o ro "${usb_disk}${k8_part}" /tmp

    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    if cp /tmp/config-file /mnt/etc/cloud/; then

        CONFIG_FILE="/mnt/etc/cloud/config-file"

        # Copy the proxy settings to /etc/environment file
        if grep -q '^http_proxy=' "$CONFIG_FILE"; then
            http_proxy=$(grep '^http_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
            http_proxy=$(echo "$http_proxy" | sed 's/^"//; s/"$//')
            ! echo "$http_proxy" | grep -q '^""$' &&  echo "http_proxy=$http_proxy" >> /mnt/etc/environment
        fi

        if grep -q "https_proxy" "$CONFIG_FILE"; then
            https_proxy=$(grep '^https_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
            https_proxy=$(echo "$https_proxy" | sed 's/^"//; s/"$//')
            ! echo "$https_proxy" | grep -q '^""$' &&  echo "https_proxy=$https_proxy" >> /mnt/etc/environment
        fi

        if grep -q '^no_proxy=' "$CONFIG_FILE"; then
            no_proxy=$(grep '^no_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
            ! echo "$no_proxy" | grep -q '^""$' &&  echo "no_proxy=$no_proxy" >> /mnt/etc/environment
        fi

        if grep -q "HTTP_PROXY" "$CONFIG_FILE"; then
            HTTP_PROXY=$(grep '^HTTP_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
            HTTP_PROXY=$(echo "$HTTP_PROXY" | sed 's/^"//; s/"$//')
            ! echo "$HTTP_PROXY" | grep -q '^""$' &&  echo "HTTP_PROXY=$HTTP_PROXY" >> /mnt/etc/environment
        fi

        if grep -q '^HTTPS_PROXY=' "$CONFIG_FILE"; then
            HTTPS_PROXY=$(grep '^HTTPS_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
            HTTPS_PROXY=$(echo "$HTTPS_PROXY" | sed 's/^"//; s/"$//')
            ! echo "$HTTPS_PROXY" | grep -q '^""$' &&  echo "HTTPS_PROXY=$HTTPS_PROXY" >> /mnt/etc/environment
        fi
    
        if grep -q '^NO_PROXY=' "$CONFIG_FILE"; then
            NO_PROXY=$(grep '^NO_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
            ! echo "$NO_PROXY" | grep -q '^""$' &&  echo "NO_PROXY=$NO_PROXY" >> /mnt/etc/environment
        fi
        umount /mnt
	umount /tmp
        success "Proxy Settings updated"
        return 0
    else
	umount /mnt
	umount /tmp
        success "Proxy Settings Failed"
        return 1
    fi
}

# Update  SSH config settings
update_ssh_settings() {
    echo -e "${BLUE}Updating the SSH Settings!!${NC} [6/9]" 

    setup_proxy_settings
    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    # update the rke2 path
    sed -i 's|^PATH="\(.*\)"$|PATH="\1:/var/lib/rancher/rke2/bin"|' /mnt/etc/environment

    # SSH Configure
    if grep -q '^ssh_key=' "$CONFIG_FILE"; then
        ssh_key=$(sed -n 's/^ssh_key="\?\(.*\)\?"$/\1/p' "$CONFIG_FILE")
        user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)
        # Write the SSH key to authorized_keys
        if echo "$ssh_key" | grep -q '^""$'; then
            echo "No SSH Key provided skipping the ssh configuration"
        else
            chroot /mnt /bin/bash <<EOT
        set -e
        # Configure the SSH for the user $user_name
        su - $user_name 
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
	cat <<EOF >> ~/.ssh/authorized_keys
$ssh_key
EOF
        chmod 600 ~/.ssh/authorized_keys
        # export the /etc/enviroment values to .bashrc
	echo "source /etc/environment" >> /home/$user_name/.bashrc
        echo "export KUBECONFIG" >> /home/$user_name/.bashrc
        #exit the su -$user_name
        exit
EOT
            # shellcheck disable=SC2181
            if [ "$?" -eq 0 ]; then
                success "SSH-KEY Configuration Success"
            else
                failure "SSH-KEY Configuration Failure!!"
                return 1 
            fi
        fi
    fi
    umount /mnt
    return 0
}

# Change the boot order to disk
boot_order_chage_to_disk() {
    echo -e "${BLUE}Changing the Boot order to disk!!${NC} [9/9]" 

    boot_order=$(efibootmgr -D)
    echo "$boot_order"
    usb_boot_number=$(efibootmgr | grep -i "Bootcurrent" | awk '{print $2}')

    boot_order=$(efibootmgr | grep -i "Bootorder" | awk '{print $2}')

    # Convert boot_order to an array and remove , between the entries
    IFS=',' read -ra boot_order_array <<<"$boot_order"

    # Remove PXE boot entry from Array
    final_boot_array=()
    for element in "${boot_order_array[@]}"; do
        if [[ "$element" != "$usb_boot_number" ]]; then
            final_boot_array+=("$element")
        fi
    done

    # Add the PXE  boot entry to the end of the boot order array
    final_boot_array+=("$usb_boot_number")

    # Join the elements of boot_order_array into a comma-separated string
    final_boot_order=$(
        IFS=,
        echo "${final_boot_array[*]}"
    )

    #remove trail and leading , if preset
    final_boot_order=$(echo "$final_boot_order" | sed -e 's/^,//;s/,$//')

    echo "final_boot order--->" "$final_boot_order"

    # Update the boot order using efibootmgr

    if efibootmgr -o "$final_boot_order"; then
        success "Made Disk as first boot and USB boot at end"
        #Make UEFI boot as inactive
        efibootmgr -b "$usb_boot_number" -A
        boot_order=$(efibootmgr)
        echo "$boot_order"
    else
        failure "Boot order change not successful,Please Manually Select the Disk boot option"
        return 1 
    fi
    efibootmgr
    return 0
}

# Update the MAC address under 99-dhcp.conf file
update_mac_under_dhcp_systemd() {
    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    CONFIG_FILE="/mnt/etc/systemd/network/99-dhcp-en.network"

    pub_inerface_name=$(route | grep '^default' | grep -o '[^ ]*$')
    mac=$(cat /sys/class/net/"$pub_inerface_name"/address)

    # Update the mac
    sed -i "s/Name=.*/MACAddress=$mac/" $CONFIG_FILE
    umount /mnt
    return 0

}

# Enable dm-verity on Microvisor image
enable_dm_verity() {
    echo -e "${BLUE}Enabling DM-VERITY on disk $os_disk!!${NC} [7/9]"
    dm_verity_script=/etc/scripts/enable-dmv.sh

    if bash $dm_verity_script; then
        success "DM Verity and Partitions successful on $os_disk"
    else
        failure "DM Verity and Partitions failed on $os_disk,Please check!!"
        return 1 
    fi
    return 0
}

copy_os_update_script() {

    echo -e "${BLUE}Copying os-update.sh to the OS disk!!${NC}" | tee /dev/tty0

    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    if cp /etc/scripts/os-update.sh /mnt/etc/cloud/os-update.sh; then
        success "Successfully copied os-update.sh to /opt of the OS disk"
    else
        failure "Failed to copy os-update.sh to the OS disk, please check!!"
        umount /mnt
        exit 1
    fi

    umount /mnt
}

# Check provision pre-conditions
system_readiness_check() {

    get_usb_details || return 1

    get_block_device_details || return 1
}

# Configure the system with username/proxy/cloud-init files
platform_config_manager() {

    install_cloud_init_file || return 1

    copy_os_update_script || return 1

    create_user || return 1

    update_ssh_settings || return 1

    update_mac_under_dhcp_systemd || return 1
}

# Post installation tasks
system_finalizer() {

    boot_order_chage_to_disk || return 1

    dump_logs_to_usb || return 1
}

# Progress Bar Function
show_progress_bar() {
    progress=$1
    message=$2

    # Calculate percentage
    percentage=$(( (progress * 100) / TOTAL_PROVISION_STEPS ))

    # Calculate number of green and red characters
    green_chars=$(( (progress * BAR_WIDTH) / TOTAL_PROVISION_STEPS ))
    red_chars=$(( BAR_WIDTH - green_chars-1 ))
    padded_status_message=$(printf "%-*s" "$MAX_STATUS_MESSAGE_LENGTH" "$message")
    green_bar=$(printf "%0.s#" $(seq 1 $green_chars))
    red_bar=$(printf "%0.s-" $(seq 1 $red_chars))
    progress_line=$(printf "\r\033[K${YELLOW}%s${NC} [${GREEN}%s${YELLOW}%s${NC}] %3d%%" \
        "$padded_status_message" "$green_bar" "$red_bar" "$percentage")
    printf "%b" "$progress_line" | tee /dev/tty0
}

# Main function
main() {

    # Print the provision flow with progress status bar with provisions steps 
    # Step 1: System Readniness Check 
    PROVISION_STEP=0
    show_progress_bar "$PROVISION_STEP" "System Readiness Check"
    if ! system_readiness_check  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:System not in ready state for Provision,Please check $LOG_FILE for more details,.Aborting.${NC}" | tee /dev/tty0
        exit 1
    fi
    PROVISION_STEP=1
    show_progress_bar "$PROVISION_STEP" "System Ready for Provision"

    # Step 2: Install OS on the disk 
    PROVISION_STEP=2
    show_progress_bar "$PROVISION_STEP" "OS Setup "
    if ! install_os_on_disk >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:OS Installation failed,Please check $LOG_FILE for more deatisl,Aborting.${NC}" | tee /dev/tty0
        exit 1
    fi

    # Step 3: create user,copy cloud-int,ssh-key,other configuration
    PROVISION_STEP=3
    show_progress_bar "$PROVISION_STEP" "Platform Configuration Manager"
    if ! platform_config_manager  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Platform Configuration failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty0
        exit 1
    fi

    # Step 4: Enable DM Verity on the platfoem 
    PROVISION_STEP=4
    show_progress_bar "$PROVISION_STEP" "Enable DM Verity on Platform"
    if ! enable_dm_verity  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:DM Verity Enablement Failed on platfrom,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty0
        exit 1
    fi

    # Step 5: K8S Cluster files copy to Disk
    PROVISION_STEP=5
    show_progress_bar "$PROVISION_STEP" "K8S cluster Config"
    if ! install_k8_script >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Copying K8S scripts to disk Failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty0
        exit 1
    fi

    # Step 6: Boot order change and reboot 
    PROVISION_STEP=6
    show_progress_bar "$PROVISION_STEP" "Post Install Setup"
    if ! system_finalizer  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Post install Setup Failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty0
        exit 1
    fi

    PROVISION_STEP=7
    show_progress_bar "$PROVISION_STEP" ""
    sync

    # Final bar completion and message
    show_progress_bar "$TOTAL_PROVISION_STEPS" "Complete!" | tee /dev/tty0

}
##### Main Execution #####
echo -e "${BLUE}Started the OS Provisioning, it will take a few minutes. Please wait!!!${NC}" | tee /dev/tty0
sleep 5
main
success "\nOS Provisioning Done!!!"
sleep 2
echo b >/host/proc/sysrq-trigger
reboot -f
