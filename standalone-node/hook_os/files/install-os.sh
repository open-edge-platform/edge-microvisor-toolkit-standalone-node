#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


set -x
###@Global Variable###########
usb_disk=""
usb_devices=""
usb_count=""
blk_devices=""
os_disk=""
os_part=5
k8_part=6
os_efi_part=1
os_rootfs_part=2
os_data_part=3
secondary_rootfs_disk_size=3
#############################

# Installation Function calls

# Wait for few seconds for USB emulation as hook os boots fast
detect_usb(){
count=0
# Check for 15 times, if USB not found exit the installation
while [ "$count" -le 15 ]
do
    usb_devices=$(lsblk -o NAME,TYPE,SIZE,RM | grep -i disk | awk '$1 ~ /sd*/ {if ($3 !="0B" && $4 ==1)  {print $1}}')
    usb_count=$(echo "$usb_devices" | wc -l)
    # If Usb device found break
    if [  -n "$usb_count" ]; then
        for disk_name in ${usb_devices}
        do
            # Bootable USB must have 6 partitions, ignore otherwise
            total_disk_part=$(lsblk -l "/dev/$disk_name" | grep -c "^$(basename "/dev/$disk_name")[0-9]")
            if [ "$total_disk_part" -eq 6 ]; then
                usb_disk="/dev/$disk_name"
                echo "$usb_disk"
                break 2
            else
                continue
            fi
        done
     fi
     sleep 1
     count=$((count+1))
done

}

# Get the usb disk where the OS image and K8* scripts copied
get_usb_details(){

#check if the USB detected at Hook OS
usb_disk=$(detect_usb)

# Exit if no USB device found
if [ -z "$usb_disk" ]; then
    echo "No valid USB device found,exiting the installation"
    exit 1
fi
echo "found the USB Device $usb_disk"

# Check partition 5 and 6 has OS and K8 Scripts data, if not exit the installation
mount -o ro "${usb_disk}${os_part}" /mnt 

if ! ls /mnt/*.raw.gz >/dev/null 2>&1; then
    echo "OS Image File not Found,exiting the installation"
    umount /mnt
    exit 1
else
    umount /mnt
fi 
mount -o ro "${usb_disk}${k8_part}" /mnt

if ! ls /mnt/sen*.tar.gz >/dev/null 2>&1; then
    echo "K8* Script File not Found,exiting the installation"
    umount /mnt
    exit 1
else
    if ! ls /mnt/config-file >/dev/null 2>&1; then 
        echo "configuration file not Found,exiting the installation"
	umount /mnt
	exit 1
    fi
    umount /mnt
fi

}

# Get the list of block devices on the device and choose the best disk for installation
get_block_device_details(){

# List of block devices attached to system,ignore USB and loop back devices
blk_devices=$(lsblk -o NAME,TYPE,SIZE,RM | grep -i disk | awk '$1 ~ /sd*|nvme*/ {if ($3 !="0B" && $4 ==0)  {print $1}}')
blk_dev_count=$(echo "$blk_devices" | wc -l)

if [  -z "$blk_dev_count" ]; then
    echo "No valid hard disk found for installation, exiting the installation !!"
    exit 1
fi

# If only one disk found use that for installation
if [ "$blk_dev_count" -eq 1 ]; then
    os_disk="/dev/$blk_devices"

# If more than one block disk found then
# Choose disk with smallest size
# NVME is prefered as Rank1 compared to SATA
else
    min_size_disk=$(lsblk -dn -o NAME,SIZE,RM,TYPE | awk '$3 == 0 && $4 == "disk" && $2 !="0B" {print $1, $2}' | sort -hk2,2 -k1,1 | awk 'NR==1 {min=$2} $2 == min {print "/dev/" $1; exit}'
)
    os_disk="$min_size_disk"
fi

# Clear the disk partitons
for disk_name in ${blk_devices}
do
    dd if=/dev/zero of="/dev/$disk_name" bs=100M count=20
done

}

# Install the OS image 
install_os_on_disk(){

echo "USB DEVICE IS" "$usb_disk"

echo "HARD DRIVE IS" "$os_disk"

if echo "$os_disk" | grep -q "nvme"; then
  os_rootfs_part="p$os_rootfs_part"
  os_data_part="p$os_data_part"
fi

mount "$usb_disk${os_part}" /mnt

os_file=$(find /mnt -type f -name "*.raw.gz" | head -n 1)

if [  -n "$os_file" ]; then

    # Install the OS image on the Disk
    # Before install erase the disk
    dd if=/dev/zero of="$os_disk" bs=1M count=500

    gzip -dc "$os_file" | dd of="$os_disk" bs=4M && sync 
    # Check the OS image flash successful or not 
    if [ "$?" -eq 0 ]; then 
        echo "Successfuly Installed OS on the Disk $os_disk"
	umount /mnt
        partprobe $os_disk && sync 
	blockdev --rereadpt $os_disk
	sleep 5
    else
        echo "Failed to Install OS on the Disk $os_disk, please check!!"
	umount /mnt
	exit 1
    fi
else
    echo "OS image file not found in the USB , please check!!"
    umount /mnt
    exit 1
fi

}

# Create the USER for the target OS
create_user()
{
# Mount all required partitions and do chroot to OS 
mount "$os_disk$os_rootfs_part" /mnt

CONFIG_FILE="/mnt/etc/cloud/config-file"

user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)
passwd=$(grep '^passwd=' "$CONFIG_FILE" | cut -d '=' -f2)

chroot /mnt /bin/bash <<EOT

# Create the user as $user_name and add to sudo and don't ask password while sudo

useradd -m -s /bin/bash $user_name && echo "$user_name:$passwd" | chpasswd && echo '$user_name ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$user_name

if [ "$?" -eq 0 ]; then
    echo "Successfully created the user!!!"
else
    echo "Failed to create the user!!!"
    exit 1
fi
EOT
#unmount the partitions
umount /mnt
}

# Install cloud-init file on OS
install_cloud_init_file()
{
# Copy the cloud init file from Hook OS to target OS
mount "$os_disk$os_rootfs_part" /mnt
cp /etc/scripts/cloud-init.yaml /mnt/etc/cloud/cloud.cfg.d/installer.cfg
chmod +x /mnt/etc/cloud/cloud.cfg.d/installer.cfg
if [ "$?" -eq 0 ]; then
    echo "Successfuly copied the cloud-init file"
else
    echo "Fail to copy the cloud-init file,please check!!!"
    exit 1
fi

# Create the cloud-init Dsi identity
chroot /mnt /bin/bash <<EOT
touch /etc/cloud/ds-identify.cfg 
echo "datasource: NoCloud" > /etc/cloud/ds-identify.cfg
chmod 600 /etc/cloud/ds-identify.cfg

EOT
umount /mnt

}

# Install K8* script to OS disk under /opt
install_k8_script(){
# Copy the scripts from USB disk to /opt on the disk
mount -o ro "${usb_disk}${k8_part}" /tmp

# Mount the OS disk 
mount "$os_disk$os_data_part" /mnt
cp /tmp/sen-rke2-package.tar.gz /mnt/

if [ "$?" -eq 0 ]; then
    echo "Successfuly copied the K8 scripts to /opt on the disk"
else
    echo "Fail to copy the K8 scripts to /opt on the disk,please check!!!"
    exit 1
fi
umount /tmp
umount /mnt

}

# Create the OS partitions
creat_partitions_on_disk(){

# Create the OS partitions such as resize the data parttion,swap,lvm
os_partition_script=/etc/scripts/os-partition.sh
bash $os_partition_script

if [ "$?" -eq 0 ]; then
    echo "OS Partition Successful on Disk $os_disk"
else
    echo "OS Partition Failed on Disk $os_disk,Please check"
    exit 1
fi

}

# Update the Proxy and SSH config settings
update_proxy_and_ssh_settings(){
# Copy the scripts from USB disk to /opt on the disk
mount -o ro "${usb_disk}${k8_part}" /tmp

# Mount the OS disk
mount "$os_disk$os_rootfs_part" /mnt

cp /tmp/config-file /mnt/etc/cloud/

umount /tmp

CONFIG_FILE="/mnt/etc/cloud/config-file"

# Copy the proxy settings to /etc/environment file

if grep -q '^http_proxy=' "$CONFIG_FILE"; then
    http_proxy=$(grep '^http_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$http_proxy" | grep -q '^""$' &&  echo "http_proxy=$http_proxy" >> /mnt/etc/environment
fi

if grep -q "https_proxy" "$CONFIG_FILE"; then
    https_proxy=$(grep '^https_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$https_proxy" | grep -q '^""$' &&  echo "https_proxy=$https_proxy" >> /mnt/etc/environment
fi

if grep -q '^no_proxy=' "$CONFIG_FILE"; then
    no_proxy=$(grep '^no_proxy=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$no_proxy" | grep -q '^""$' &&  echo "no_proxy=$no_proxy" >> /mnt/etc/environment
fi

if grep -q "HTTP_PROXY" "$CONFIG_FILE"; then
    HTTP_PROXY=$(grep '^HTTP_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$HTTP_PROXY" | grep -q '^""$' &&  echo "HTTP_PROXY=$HTTP_PROXY" >> /mnt/etc/environment
fi

if grep -q '^HTTPS_PROXY=' "$CONFIG_FILE"; then
    HTTPS_PROXY=$(grep '^HTTPS_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$HTTPS_PROXY" | grep -q '^""$' &&  echo "HTTPS_PROXY=$HTTPS_PROXY" >> /mnt/etc/environment
fi

if grep -q '^NO_PROXY=' "$CONFIG_FILE"; then
    NO_PROXY=$(grep '^NO_PROXY=' "$CONFIG_FILE" | cut -d '=' -f2)
    ! echo "$NO_PROXY" | grep -q '^""$' &&  echo "NO_PROXY=$NO_PROXY" >> /mnt/etc/environment
fi

# SSH Configure
if grep -q '^ssh_key=' "$CONFIG_FILE"; then
    ssh_key=$(sed -n 's/^ssh_key="\?\(.*\)\?"$/\1/p' "$CONFIG_FILE")
    user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)
    # Write the SSH key to authorized_keys
    if  echo "$ssh_key" | grep -q '^""$'; then
        echo "No SSH Key provided skipping the ssh configuration"
    else
        chroot /mnt /bin/bash <<EOT
        # Configure the SSH
        su - $user_name 
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
	cat <<EOF >> ~/.ssh/authorized_keys
$ssh_key
EOF
        chmod 600 ~/.ssh/authorized_keys
        if [ "$?" -ne 0 ]; then
            echo "SSH-KEY Configuration failed!!!"
            exit 1
        else
            echo "SSH-KEY Configuration Success!!!"
        fi
EOT
    fi
fi
umount /mnt

}

# Change the boot order to disk
boot_order_chage_to_disk(){
usb_boot_number=$(efibootmgr | grep -i "Bootcurrent" | awk '{print $2}')

boot_order=$(efibootmgr | grep -i "Bootorder" | awk '{print $2}')

# Convert boot_order to an array and remove , between the entries
IFS=',' read -ra boot_order_array <<< "$boot_order"

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
final_boot_order=$(IFS=,; echo "${final_boot_array[*]}")

#remove trail and leading , if preset
final_boot_order=$(echo "$final_boot_order" | sed -e  's/^,//;s/,$//' )

echo "final_boot order--->" $final_boot_order

# Update the boot order using efibootmgr
efibootmgr -o "$final_boot_order"

if [ "$?" -eq 0 ]; then
    echo "Made Disk as first boot and USB boot at end"
    #Make UEFI boot as inactive
    efibootmgr -b $usb_boot_number -A
else
    echo "Boot order change not successful,Please Manually Select the Disk boot option"
    exit 1
fi

}

# Enable dm-verity on tiber os image
enable_dm_verity(){

dm_verity_script=/etc/scripts/enable-dmv.sh
bash $dm_verity_script

if [ "$?" -eq 0 ]; then
    echo "DM Verity and Partitions successful on $os_disk"
else
    echo "DM Verity and Partitions failed on $os_disk,Please check"
    exit 1
fi
}

# Set the SE Linux Policy
set_selinux_policy(){
mount "$os_disk$os_rootfs_part" /mnt

chroot /mnt /bin/bash <<EOT
# Set the SE linux policy to the files we touched during the provisioning
setfiles -m -v /etc/selinux/targeted/contexts/files/file_contexts /

if [ $? -eq 0 ]; then
    echo "Successfuly applied SE linux policy!!"
else
    echo "Something went wrong in SE linux policy!!!"
    exit 1
fi
EOT
#unmount the partitions
umount /mnt 

}



main(){

get_usb_details

get_block_device_details

install_os_on_disk

install_cloud_init_file

#creat_partitions_on_disk

update_proxy_and_ssh_settings

create_user

enable_dm_verity

install_k8_script

boot_order_chage_to_disk

}
#####@main@@
main

echo "Successfully completed the provisioning flow, Rebooting to OS disk!!!!!!!!"
echo b > /host/proc/sysrq-trigger
reboot -f
