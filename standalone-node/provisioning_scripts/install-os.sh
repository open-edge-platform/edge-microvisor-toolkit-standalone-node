#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -x

### Global Variables ###
usb_disk=""
usb_devices=""
# shellcheck disable=SC2034
usb_count=""
blk_devices=""
os_disk=""
os_part=5
conf_part=6
user_apps_part=7
os_rootfs_part=2
os_data_part=3
deploy_mode="real"
user_apps_data="false"
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

# Dynamically updating the cloud-init file.
TMP_YAML=$(mktemp)
CONFIG_FILE=""
CLOUD_INIT_FILE=""

: >"$LOG_FILE"

# Dump the failure logs to USB for debugging
dump_logs_to_usb() {
    # Mount the USB
    mount "${usb_disk}${conf_part}" /mnt
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
        # shellcheck disable=SC2086
        for disk_name in $usb_devices; do
            # Bootable USB has 6 partitions,ignore other disks
            if [ "$(lsblk -l "/dev/$disk_name" | grep -c "^$(basename "/dev/$disk_name")[0-9]")" -eq 7 ]; then
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
    echo -e "${BLUE}Get the USB details!!${NC}" 
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
    mount -o ro "${usb_disk}${conf_part}" /mnt
    if ! ls /mnt/config-file >/dev/null 2>&1; then
        failure "Configuration file not Found, exiting the installation."
        umount /mnt
        return 1 
    fi
    umount /mnt
    #check_mnt_mount_exist
    mount -o ro "${usb_disk}${user_apps_part}" /mnt
    if [ -d "/mnt/user-apps" ]; then
        user_apps_data="true"
    fi
    umount /mnt
    return 0
}

# Get the list of block devices on the device and choose the best disk for installation
get_block_device_details() {
    echo -e "${BLUE}Get the block device for OS installation${NC}" 

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
    # shellcheck disable=SC2086
    for disk_name in ${blk_devices}; do
        dd if=/dev/zero of="/dev/$disk_name" bs=100M count=20
	wipefs --all "/dev/$disk_name"
    done
    # Remove previous LVM's data if exist
    vgname="lvmvg"
    vgremove -f "$vgname"
    rm -rf  "/dev/${vgname:?}/"
    rm -rf  /dev/mapper/lvmvg-pv*
    dmsetup remove_all
    # Remove previous Physical volumes if exist
    for pv_disk in $(pvscan 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^\/dev\//) print $i}'); do
        echo "Removing LVM metadata from $pv_disk"
        pvremove -ff -y "$pv_disk"
    done
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
        echo -e "${BLUE}Installing $os_file on disk $os_disk!!${NC}"
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
    check_mnt_mount_exist
    mount "${usb_disk}${conf_part}" /mnt1

    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    cp /mnt1/config-file /mnt/etc/cloud/

    passwd=$(grep '^passwd=' "/mnt1/.psswd" | cut -d '=' -f2)
   
    umount /mnt1
    rm -rf /mnt1

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)

    echo -e "${BLUE}Creating the User Account!!${NC}" 
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
    echo -e "${BLUE}Installing the Cloud-init file!!${NC}" 


    CLOUD_INIT_FILE="/etc/scripts/cloud-init.yaml"

    # Update the Cloud-init file based on host type and custom configurations"
    custom_cloud_init_updates 
    sync
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
    cp /etc/scripts/k3s-setup-post-reboot.sh /mnt/etc/cloud/
    cp /etc/scripts/k3s-configure.sh /mnt/etc/cloud/
    cp /etc/scripts/sen-k3s-installer.sh /mnt/etc/cloud/

    umount /mnt
    return 0
}

# Update the Proxy settings under /etc/environment
setup_proxy_settings() {
    echo -e "${BLUE}Set the Proxy Settings!!${NC}"

    mount -o ro "${usb_disk}${conf_part}" /tmp

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
    echo -e "${BLUE}Updating the SSH Settings!!${NC}" 

    setup_proxy_settings
    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    # Update the k3s path
    sed -i 's|^PATH="\(.*\)"$|PATH="\1:/var/lib/rancher/k3s/bin"|' /mnt/etc/environment
    
    # Get the lvm_size_ingb from config-file for creating the LVM
    lvm_size=$(grep '^lvm_size_ingb=' "$CONFIG_FILE" | cut -d '=' -f2)
    lvm_size=$(echo "$lvm_size" | tr -d '"')

    # Check the deployment mode, is it for VM or Real hardware
    deploy_mode=$(grep '^deploy_envmt=' "$CONFIG_FILE" | cut -d '=' -f2)
    deploy_mode=$(echo "$deploy_mode" | tr -d '"')

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
        echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/$user_name/.bashrc
        echo "export KUBE_CONFIG_PATH=/etc/rancher/k3s/k3s.yaml" >> /home/$user_name/.bashrc
        echo "alias k='KUBECONFIG=/etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/bin/k3s kubectl'" >> /home/$user_name/.bashrc
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
    echo -e "${BLUE}Changing the Boot order to disk!!${NC}"

    # Delete the pile up Ubuntu/Emt partitions from BIOS bootMenu
    for bootnumber in $(efibootmgr | grep -iE "Linux Boot Manager|Ubuntu" | awk '{print $1}' | sed 's/Boot//;s/\*//'); do
        efibootmgr -b "$bootnumber" -B
    done
    # Delete the duplicate boot entries from bootmenu
    boot_order=$(efibootmgr -D)
    echo "$boot_order"

    # Get the rootfs
    rootfs=$(blkid | grep -Ei 'TYPE="ext4"' | grep -Ei 'LABEL="rootfs"' | awk -F: '{print $1}')

    efiboot=$(blkid | grep -Ei 'TYPE="vfat"' | grep -Ei 'LABEL="esp|uefi"' |  awk -F: '{print $1}')

    # shellcheck disable=SC2034
    if echo "$efiboot" | grep -q "nvme"; then
        osdisk=$(echo "$rootfs" | grep -oE 'nvme[0-9]+n[0-9]+' | head -n 1)
    elif echo "$efiboot" | grep -q "sd"; then
        osdisk=$(echo "$rootfs" | grep -oE 'sd[a-z]+' | head -n 1)
    fi

    # Mount all required partitions to create bootctl install entry
    check_mnt_mount_exist

    mount "${rootfs}" /mnt
    mount "$efiboot" /mnt/boot/efi
    mount --bind /dev /mnt/dev
    mount --bind /dev/pts /mnt/dev/pts
    mount --bind /proc /mnt/proc
    mount --bind /sys /mnt/sys
    mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

    if chroot /mnt /bin/bash <<EOT
    set -e
    bootctl install
EOT
    then
        success "Made Disk as first boot option"
	#unmount the partitions
        for mount in $(mount | grep '/mnt' | awk '{print $3}' | sort -nr); do
            umount "$mount"
        done
        return 0
    else
        failure "Boot entry create failed,Please check!!"
	#unmount the partitions
        for mount in $(mount | grep '/mnt' | awk '{print $3}' | sort -nr); do
            umount "$mount"
        done
        return 1
   fi
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
    echo -e "${BLUE}Enabling DM-VERITY on disk $os_disk!!${NC}"
    dm_verity_script=/etc/scripts/enable-dmv.sh

    if bash $dm_verity_script "$lvm_size"; then
        success "DM Verity and Partitions successful on $os_disk"
    else
        failure "DM Verity and Partitions failed on $os_disk,Please check!!"
        return 1 
    fi
    return 0
}

# Dynamically update the cloud-init file based on User configuration and host type
custom_cloud_init_updates() {
    echo -e "${BLUE}Updating the cloud-init file !${NC}"

    # Get the custom details from config-file
    check_mnt_mount_exist
    mount -o ro "${usb_disk}${conf_part}" /mnt

    config_file="/mnt/config-file"

    cp "$config_file" /etc/scripts
    CONFIG_FILE="/etc/scripts/config-file"

    umount /mnt

    # Check the host type and update cloud-init accordingly
    host_type=$(grep '^host_type=' "$CONFIG_FILE" | cut -d '=' -f2)
    host_type=$(echo "$host_type" | tr -d '"')
    huge_page_size=$(grep '^huge_page_config=' "$CONFIG_FILE" | cut -d '=' -f2 | tr -d '"')

    # Update cloud-init file to start k3s stack installations for hosty type kubernetes
    if [ "$host_type" == "kubernetes" ]; then

	# If huge page value set make this line as start of cloud-init file
        if [ -n "$huge_page_size" ]; then
            line0="echo $(( huge_page_size )) | tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
        else
            line0=""
        fi
	# K3 configuration
        line1="chmod +x /etc/cloud/k3s-configure.sh"
        line2="bash /etc/cloud/k3s-configure.sh"

        awk -v line0="$line0" -v line1="$line1" -v line2="$line2" '
        BEGIN {
            runcmd = 0
            in_block = 0
        }

        /^runcmd:/ { runcmd = 1 }

        runcmd && /^  - \|/ { in_block = 1 }
        {
            print
        }

        in_block && $0 !~ /^  / {
            if (line0 != "") print "    " line0
            print "    " line1
            print "    " line2
            in_block = 0
            runcmd = 0
        }

        END {
            if (in_block) {
                if (line0 != "") print "    " line0
                     print "    " line1
                     print "    " line2
            }
        }
        ' "$CLOUD_INIT_FILE" > "${CLOUD_INIT_FILE}.tmp" && mv "${CLOUD_INIT_FILE}.tmp" "$CLOUD_INIT_FILE"

    elif [ "$host_type" == "container" ]; then 
         # TODO: will be expand in future
	 echo "host type is container , docker services will start"
    fi

    # Check for the custom cloud-init changes provided by User
    # Since the config-file is mix of bash and yaml,extract yaml text to tmp yaml file
    awk '/^[[:space:]]*(services|write_files|runcmd):/ { in_yaml = 1 }
       in_yaml { print }' "$CONFIG_FILE" > "$TMP_YAML"

    parse_custom_cloud_init_section
}
# Parse the custom cloud-init section and add the commands to cloud-init section if present
parse_custom_cloud_init_section () {
   
    # Parse the services && runcmd sections and get the new additions	
    additions="$(build_runcmd_lines)"

    awk -v additions="$additions" '
    BEGIN {
      split(additions, extra, "\n")
      added = 0
    }

    /^runcmd:/ { print; next }

    /^  - \|/ {
      print
      in_block = 1
      next
    }

    {
      if (in_block && $0 !~ /^    / && !added) {
        for (i in extra) if (length(extra[i]) > 0) print extra[i]
        added = 1
        in_block = 0
      }
      print
    }

    END {
      if (in_block && !added) {
        for (i in extra) if (length(extra[i]) > 0) print extra[i]
      }
    }
  ' "$CLOUD_INIT_FILE" > "${CLOUD_INIT_FILE}.tmp" && mv "${CLOUD_INIT_FILE}.tmp" "$CLOUD_INIT_FILE"
  echo "Custom section updated Successfully"

  # Check if any new files are added by User, If yes add them in required path
  write_custom_files_to_disk

}

# Adding custom files to disk from custom cloud-init file given by User
write_custom_files_to_disk () {
    count=$(yq e '.write_files | length' "$TMP_YAML" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ] && echo "No custom write_files found" && return

    # Enable the Selinux policies
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    echo "custom write files found..."
    for i in $(seq 0 $((count - 1))); do
    path=$(yq e ".write_files[$i].path" "$TMP_YAML")
    perms=$(yq e ".write_files[$i].permissions // \"0644\"" "$TMP_YAML")
    content=$(yq e -r ".write_files[$i].content" "$TMP_YAML")

    if [ "$path" = "null" ] || [ -z "$content" ]; then
      echo "Skipping file $i: missing path/content"
      continue
    fi
    echo "Writing $path with permissions $perms"
    echo "$content" > "/mnt/$path"
    chmod "$perms" "/mnt/$path"
  done
  echo "All custome files written successfully to disk"
  umount /mnt
}


# Add custom cloud-init services based on user inputs
build_runcmd_lines () {
    
    # Apend the content to lines for adding to cloud-init file
    lines=""

    # Enable custom services if provided
    enable=$(yq e '.services.enable[]' "$TMP_YAML" 2>/dev/null || true)
    for svc in $enable; do
        lines="$lines\n    systemctl enable $svc"
    done

    # Disable custom services if provided
    disable=$(yq e '.services.disable[]' "$TMP_YAML" 2>/dev/null || true)
    for svc in $disable; do
        lines="$lines\n    systemctl disable $svc"
    done

    # Get the commands from runcmd section and append it to cloud-init file
    user_cmds=$(awk '
    /^[[:space:]]*runcmd:/ { in_block = 1; next }
    in_block {
      if (/^[^[:space:]]/ && $0 !~ /^-/) exit
      if ($0 ~ /^#|^[[:space:]]*$/) next
      gsub(/^[[:space:]]*-[[:space:]]*/, "")
      print "    " $0
    }
    ' "$CONFIG_FILE")

  # Append the custom services at the end of the cloud-init file section
  if [ -n "$user_cmds" ]; then
    lines="$lines\n$user_cmds"
  fi
  echo -e "$lines" | sed '/^[[:space:]]*$/d'
}


# Create OS Partitions for virtual edge node
create_os-partition() {
    echo -e "${BLUE}Creating the OS Partitions on disk $os_disk!!${NC}"
    os_partition_script=/etc/scripts/os-partition.sh

    if bash $os_partition_script; then
        success "OS Partitions successful on $os_disk"
    else
        failure "OS Partitions failed on $os_disk,Please check!!"
        return 1
    fi
    # Enable the Selinux policies
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    chroot /mnt /bin/bash <<EOT
    # Set the SE linux policy to the files we touched during the provisioning
    setfiles -m -v /etc/selinux/targeted/contexts/files/file_contexts /
EOT
    return 0

}

# Copy user-apps to OS disk under /opt
copy_user_apps() {
    echo -e "${BLUE}Copying user-apps!!${NC}"

    mkdir -p /mnt2
    mount -o ro "${usb_disk}${user_apps_part}" /mnt2

    # Mount the OS disk
    check_mnt_mount_exist

    if mount "$os_disk$os_data_part" /mnt && cp -r /mnt2/user-apps/ /mnt/; then
        success "Successfuly copied the user-apps on the disk"
    else
        failure "Fail to copy user-apps on the disk,please check!!!"
	umount /mnt2
        umount /mnt
        rm -rf /mnt2
        return 1
    fi
    umount /mnt2
    umount /mnt
    rm -rf /mnt2
    sync
    return 0
}

copy_os_update_script() {

    echo -e "${BLUE}Copying os-update.sh to the OS disk!!${NC}" 

    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    if cp /etc/scripts/os-update.sh /mnt/etc/cloud/os-update.sh; then
        success "Successfully copied os-update.sh to /etc/cloud of the OS disk"
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

    boot_order_chage_to_disk || return 1
}

# Post installation tasks
system_finalizer() {

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
    printf "%b" "$progress_line" | tee /dev/tty1
}

# Main function
main() {

    # Print the provision flow with progress status bar with provisions steps 
    # Step 1: System Readniness Check 
    PROVISION_STEP=0
    show_progress_bar "$PROVISION_STEP" "System Readiness Check"
    if ! system_readiness_check  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:System not in ready state for Provision,Please check $LOG_FILE for more details,.Aborting.${NC}" | tee /dev/tty1
        exit 1
    fi
    PROVISION_STEP=1
    show_progress_bar "$PROVISION_STEP" "System Ready for Provision"

    # Step 2: Install OS on the disk 
    PROVISION_STEP=2
    show_progress_bar "$PROVISION_STEP" "OS Setup "
    if ! install_os_on_disk >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:OS Installation failed,Please check $LOG_FILE for more deatisl,Aborting.${NC}" | tee /dev/tty1
        exit 1
    fi

    # Step 3: create user,copy cloud-int,ssh-key,other configuration
    PROVISION_STEP=3
    show_progress_bar "$PROVISION_STEP" "Platform Configuration Manager"
    if ! platform_config_manager  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Platform Configuration failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        exit 1
    fi

    # Case the deployment for Virtual edgenode or Real hardware
    if [ "$deploy_mode" == "ven" ]; then
        # Step 4: Enable OS-Partitions on the platfoem 
        PROVISION_STEP=4
        show_progress_bar "$PROVISION_STEP" "Enable OS-Partitions on Platform"
        if ! create_os-partition  >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}\nERROR:OS-Partitions Creatation Failed on platfrom,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty1
            exit 1
        fi
    else
        # Step 4: Enable DM Verity on the platfoem
        PROVISION_STEP=4
        show_progress_bar "$PROVISION_STEP" "Enable DM Verity on Platform"
        if ! enable_dm_verity  >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}\nERROR:DM Verity Enablement Failed on platfrom,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty1
           exit 1
        fi
    fi

    # Step 5: Copy user-apps data to Disk
    PROVISION_STEP=5
    show_progress_bar "$PROVISION_STEP" "Copying user-apps"
    if [ "$user_apps_data" == "true" ]; then
        if ! copy_user_apps >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}\nERROR:Copying user-apps to disk Failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        exit 1
        fi
    fi

    # Step 6: Post install Setup and reboot 
    PROVISION_STEP=6
    show_progress_bar "$PROVISION_STEP" "Post Install Setup"
    if ! system_finalizer  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Post install Setup Failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        exit 1
    fi

    PROVISION_STEP=7
    show_progress_bar "$PROVISION_STEP" ""
    sync

    # Final bar completion and message
    show_progress_bar "$TOTAL_PROVISION_STEPS" "Complete!" | tee /dev/tty1

}
##### Main Execution #####
echo -e "${BLUE}Started the OS Provisioning, it will take a few minutes. Please wait!!!${NC}" | tee /dev/tty1
sleep 5
main
success "\nOS Provisioning Done!!!"
sleep 2
echo b >/host/proc/sysrq-trigger
reboot -f
