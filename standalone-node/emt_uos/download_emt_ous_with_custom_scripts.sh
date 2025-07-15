#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


# Download the Edge Microvisor Toolkit from open source no-auth file server
# The file server URL is defined in FILE_RS_URL
#FILE_RS_URL="https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository"
#EMT_BUILD_DATE=20250604
#EMT_FILE_NAME="microvisor/uos/emt_uos_x86_64_${EMT_BUILD_DATE}"
#EMT_RAW_GZ="${EMT_FILE_NAME}.tar.gz"


#curl -k --noproxy '' ${FILE_RS_URL}/${EMT_RAW_GZ} -o uos.tar.gz || { echo "download of uos failed,please check";exit 1;}

# TO DO: Use no-auth file server registry to download the Edge Microvisor Toolkit image
#FILE_RS_URL="https://af01p-png.devtools.intel.com/artifactory/edge_system-png-local/images"
#EMT_BUILD_DATE=20250625.0555
#EMT_FILE_NAME="emt_uos_image/emt_uos_x86_64_${EMT_BUILD_DATE}"

FILE_RS_URL="https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository"
EMT_BUILD_DATE=20250710
EMT_FILE_NAME="microvisor/uos/emb_uos_x86_64_${EMT_BUILD_DATE}"
EMT_RAW_GZ="${EMT_FILE_NAME}.tar.gz"

curl -k --noproxy '' ${FILE_RS_URL}/${EMT_RAW_GZ} -o uos.tar.gz || { echo "download of uos failed,please check";exit 1;}

echo "Current working directory is: $PWD"

if [ ! -d uOS ]; then
    mkdir -p uOS || { echo "Failed to create uOS directory"; exit 1; }
else
   rm -rf uOS/*
fi


tar -xzvf uos.tar.gz -C uOS || { echo "Failed to extract uos.tar.gz"; exit 1; }

vmlinuz_file=$(find uOS -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' | head -n1)
initramfs_file=$(find uOS -maxdepth 1 -type f -name 'initramfs*' -printf '%f\n' | head -n1)

cp uOS/"$vmlinuz_file"  vmlinuz-x86_64 || { echo "download of vmlinuz-x86_64"; exit 1; } 
cp uOS/"$initramfs_file" initramfs-x86_64 || { echo "download of initramfs-x86_64"; exit 1; } 

echo "Successfully Downloaded emt-ous initramfs && vmlinux files"

# cleanup the files
rm -rf uos.tar.gz uOS/*

# Add custom provision scripts to init-rams file

# Create init-ramfs extract directory

if [ ! -d initramfs_extract ]; then
    mkdir -p initramfs_extract
else
   sudo rm -rf initramfs_extract
fi

# Extract the initramfs content
zcat initramfs-x86_64 | cpio -idmv -D initramfs_extract > /dev/null 2>&1

echo "initramfs-x86_64 file extracted successuly"

rm initramfs-x86_64
mkdir -p initramfs_extract/rootfs-tmp
gzip -d initramfs_extract/rootfs.tar.gz ||  { echo "extraction of rootfs.tar.gz failed"; exit 1; }

mv initramfs_extract/rootfs.tar initramfs_extract/rootfs-tmp

# Copy the provision scripts for EMT-S installation
mkdir -p initramfs_extract/rootfs-tmp/etc/scripts
mkdir -p initramfs_extract/rootfs-tmp/etc/systemd/system


cp ../provisioning_scripts/*.sh initramfs_extract/rootfs-tmp/etc/scripts/
cp ../provisioning_scripts/*.yaml initramfs_extract/rootfs-tmp/etc/scripts/
cp ../provisioning_scripts/start-provision.service initramfs_extract/rootfs-tmp/etc/systemd/system/

# Copy the custom provision script to rootfs
pushd initramfs_extract/rootfs-tmp/ || exita

# Create the service script to start the provision service
mkdir -p etc/systemd/system/default.target.wants

ln -sf ../start-provision.service etc/systemd/system/default.target.wants/start-provision.service

tar -uf rootfs.tar  ./etc/scripts/ || { echo "Adding custom provision scripts to rootfs failed"; exit 1; }
tar -uf rootfs.tar  ./etc/systemd/system/start-provision.service || { echo "Adding emt-s provision service scripts to rootfs failed"; exit 1; }
tar -uf rootfs.tar ./etc/systemd/system/default.target.wants/start-provision.service || { echo "Enable emt-s provision service scripts to rootfs failed"; exit 1; }

gzip -c rootfs.tar > ../rootfs.tar.gz
popd || exit

# Remove the rootfs-tmp content
rm -r initramfs_extract/rootfs-tmp/*

pushd initramfs_extract/ || exit
sudo tar -xzf rootfs.tar.gz > /dev/null 2>&1
find . |sudo cpio -o -H newc | gzip -9 > ../initramfs-x86_64 || { echo "Failed to create initramfs with custom scripts"; exit 1; }
popd || exit
sudo rm -rf initramfs_extract

echo "Successully injected the custom provision scripts to initramfs"



