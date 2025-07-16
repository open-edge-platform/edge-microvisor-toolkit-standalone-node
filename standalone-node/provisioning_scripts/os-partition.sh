#!/bin/sh

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2086  # Double quote to prevent globbing and word splitting - intentionally not quoted for disk operations
# shellcheck disable=SC2002  # Useless cat - using cat for readability and consistency
# shellcheck disable=SC2181  # Check exit code directly - using $? for compatibility with sh

set -x

##global variables#####
os_disk=""
part_number=""
data_part_number=""
data_partition_disk=""
rootfs_partition_disk=""
secondary_rootfs_disk_size=3
######################

#swap partition creation
create_swap_partition(){
disk=$1
SWAP_PART_SIZE_START=$2
SWAP_PART_SIZE_END=$3
data_part_num=$4
swap_part_number=$((data_part_num+2))
parted "${disk}" --script mkpart primary linux-swap "${SWAP_PART_SIZE_START}GB"  "${SWAP_PART_SIZE_END}GB"
#get the partition number
if echo "$disk" | grep -q "nvme"; then
    swap_part="p${swap_part_number}"
else
    swap_part="${swap_part_number}"
fi
partprobe "${disk}"
mkswap "/dev/${os_disk}${swap_part}"
swapon "/dev/${os_disk}${swap_part}"

#get the UUID
uuid=$(blkid | grep swap | grep primary | awk '{print $2}'|awk -F= '{print $2}'|tr -d '"')
if [ -z "$uuid" ]; then
    echo "Faild to create the swap partiton!!!!"
    exit 1
else
    #add entry for swap partition in fstab
   
    #Before mouting the file system check if the file system exist or not from user space, if not wait for few seconds
    count=0
    partprobe "${disk}" 
    while [ ! -b "$rootfs_partition_disk" ] && [ "$count" -le 9 ]; do
	    sleep 1 && count=$((count+1))
    done
    if [ "$count" -ge 10 ]; then 
        echo "Faild to mount the root file system for for swap entry update $disk"
        exit 1
    fi
    mount $rootfs_partition_disk /mnt
    mount --bind /dev /mnt/dev
    mount --bind /dev/pts /mnt/dev/pts
    mount --bind /proc /mnt/proc
    mount --bind /sys /mnt/sys
    echo "UUID=$uuid swap swap default 0 2" >> /mnt/etc/fstab
    status=$(cat "/mnt/etc/fstab" | grep -c "swap")
    if [ "$status" -ge 1 ]; then
        echo "Successfuly created the swap partition for the disk $disk"
    else
	echo "Faild to update swap partition in /etc/fstab for the disk $disk"
	exit 1
    fi	
    #unmount the partitions
    for mount in $(mount | grep '/mnt' | awk '{print $3}' | sort -nr); do
        umount "$mount"
    done
fi
}
#disk partition for SWAP and LVM
partition_disk(){
ram_size=$1
disk_size=$2

disk="/dev/$os_disk"

swap_size=$(awk -v r="$ram_size" 'BEGIN { printf "%d\n", sqrt(r) }')

if [ "$swap_size" -ge "$disk_size" ]; then
    echo "Looks the Disk size is very Minimal and can't proceed with partition!!!!"
    exit 1
fi

#get the partition for the rootfs for side B for A/B upgrades
secondary_rootfs_disk_num=$((data_part_number+1))
if echo "$disk" | grep -q "nvme"; then
    # shellcheck disable=SC2034  # secondary_rootfs_disk is used for A/B upgrade functionality
    secondary_rootfs_disk="p${secondary_rootfs_disk_num}"
else
    # shellcheck disable=SC2034  # secondary_rootfs_disk is used for A/B upgrade functionality  
    secondary_rootfs_disk="${secondary_rootfs_disk_num}"
fi

#get the last partition end point
data_part_end=$(parted -m $disk unit GB print | grep "^$data_part_number" | cut -d: -f3 | sed 's/GB//')
if echo "$data_part_end" | grep -qE '^[0-9]+\.[0-9]+$'; then
    data_part_end=$(printf "%.0f" "$data_part_end")
fi
#add data_part_end secondary_rootfs disk size and swap_size to get toatl size in use
total_size_inuse=$(awk -v a="$data_part_end" -v b="$swap_size" -v c="$secondary_rootfs_disk_size" 'BEGIN { print a + b + c }')
#calculate the size for expanding the data partition
data_part_end_size=$(awk -v d="$disk_size" -v t="$total_size_inuse" 'BEGIN { print d - t }')
#secondary rootfs partitions for A/B day2 upgrades
secondary_rootfs_disk_end=$((data_part_end_size+secondary_rootfs_disk_size))
parted ---pretend-input-tty "${disk}" \
    resizepart "$data_part_number" "${data_part_end_size}GB" \
   	mkpart primary ext4 "${data_part_end_size}GB" "${secondary_rootfs_disk_end}GB"
if [ $? -ne 0 ]; then
    echo "Partition resize for the disk ${disk} failed"
    exit 1
else
    echo "Partition resize for the disk ${disk} Successful!!"
fi
partprobe "${disk}"

#get the end size of the last partition from the  disk
last_partition_end=$(parted -ms $disk  print | tail -n 1 | awk -F: '{print $3}' | sed 's/GB$//')
if echo "$last_partition_end" | grep -qE '^[0-9]+\.[0-9]+$'; then
        last_partition_end=$(printf "%.0f" "$last_partition_end")
fi
swap_partition_size_end=$((last_partition_end+swap_size))

#create SWAP
create_swap_partition "${disk}" "${last_partition_end}" "${swap_partition_size_end}" "${data_part_number}"

#finally expand the data partition using resize2fs
e2fsck -f -y "$data_partition_disk"
resize2fs "$data_partition_disk"
if [ $? -ne 0 ]; then
    echo "Partition resize for the disk ${disk} failed"
    exit 1
else
    echo "Partition resize for the disk ${disk} Successful!!"
    fi
}

#######@main

echo "--------Starting the SWAP and LVM partition on Edge Microvisor Toolkit---------"

#get the rootfs partition from the disk

rootfs_partition_disk=$(blkid | grep -i rootfs | grep -i ext4 |  awk -F: '{print $1}')
data_partition_disk=$(blkid | grep -i "edge_persistent" | grep -i ext4 |  awk -F: '{print $1}')

if echo "$rootfs_partition_disk" | grep -q "nvme"; then
    os_disk=$(echo "$rootfs_partition_disk" | grep -oE 'nvme[0-9]+n[0-9]+' | head -n 1)
    # shellcheck disable=SC2034  # part_number used for disk naming consistency
    part_number="p"
    data_part_number=$(blkid | grep "edge_persistent" | awk -F'[/:]' '{print $3}'| awk -F'p' '{print $2}')
else
    os_disk=$(echo "$rootfs_partition_disk" | grep -oE 'sd[a-z]+' | head -n 1)
    # shellcheck disable=SC2034  # part_number used for disk naming consistency
    part_number=""
    data_part_number=$(blkid | grep "edge_persistent" | awk -F'[/:]' '{print $3}' | sed 's/[^0-9]*//g')
fi

#check the ram size && decide the sawp size based on it

ram_size=$(free -g | grep -i mem | awk '{ print $2 }')

#get the total rootfs partition disk size

#if there were any problems when the ubuntu was streamed.
printf 'OK\n'  | parted ---pretend-input-tty -m  "/dev/$os_disk" p
printf 'Fix\n' | parted ---pretend-input-tty -m  "/dev/$os_disk" p

total_disk_size=$(parted -m "/dev/$os_disk" unit GB print | grep "^/dev" | cut -d: -f2 | sed 's/GB//')
if echo "$total_disk_size" | grep -qE '^[0-9]+\.[0-9]+$'; then
    total_disk_size=$(printf "%.0f" "$total_disk_size")
fi

#partition the disk with swap and rootfsb 

partition_disk "$ram_size" "$total_disk_size"  
