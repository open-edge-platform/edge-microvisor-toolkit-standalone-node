#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Download the Edge Microvisor Toolkit uOS(EMB) from open source no-auth file server
# The file server URL is defined in FILE_RS_URL

export PLATFORM_TYPE="${1:-PTL}"

FILE_RS_URL="https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository"

# Select the uOS image based on the platform type PTL or RPL/BTL
if [ "$PLATFORM_TYPE" == "PTL" ]; then
    # PTL Platform (To be updated with PV release images)
    # RPL/BTL Platform
    EMB_BUILD_DATE=20260526
    EMB_FILE_NAME="microvisor/uos/26.06/emb_uos_x86_64_${EMB_BUILD_DATE}"
    EMB_RAW_GZ="${EMB_FILE_NAME}.tar.gz"
    EMB_IMAGE_URL="${FILE_RS_URL}/${EMB_RAW_GZ}"
    echo "PTL Platform uOS is selected"
else
    # RPL/BTL Platform
    EMB_BUILD_DATE=20260526
    EMB_FILE_NAME="microvisor/uos/26.06/emb_uos_x86_64_${EMB_BUILD_DATE}"
    EMB_RAW_GZ="${EMB_FILE_NAME}.tar.gz"
    EMB_IMAGE_URL="${FILE_RS_URL}/${EMB_RAW_GZ}"
    echo "RPL/BTL Platform uOS is selected"
fi

curl -k --noproxy '' ${EMB_IMAGE_URL} -o uos.tar.gz || { echo "download of uos failed, please check";exit 1;}

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

echo "Successfully Downloaded emt-uOS initramfs && vmlinux files"

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

# Bundle yq binary into the hook OS so write_files parsing works during provisioning.
# Only download if yq is not already present in the extracted rootfs (future uOS versions may ship it).
mkdir -p initramfs_extract/rootfs-tmp/usr/bin
if tar -tf initramfs_extract/rootfs-tmp/rootfs.tar ./usr/bin/yq > /dev/null 2>&1; then
    echo "yq already present in uOS rootfs, skipping download"
else
    YQ_VERSION="v4.44.3"
    YQ_BINARY="yq_linux_amd64"
    YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"
    echo "yq not found in uOS rootfs, downloading ${YQ_VERSION}..."
    if curl -fsSL "${YQ_URL}" -o initramfs_extract/rootfs-tmp/usr/bin/yq; then
        chmod +x initramfs_extract/rootfs-tmp/usr/bin/yq
        echo "yq downloaded and staged successfully"
    else
        echo "WARNING: Failed to download yq; write_files entries in config-file will not be written to disk during provisioning"
    fi
fi

# Copy the custom provision script to rootfs
pushd initramfs_extract/rootfs-tmp/ || exit

# Create the service script to start the provision service
mkdir -p etc/systemd/system/default.target.wants

ln -sf ../start-provision.service etc/systemd/system/default.target.wants/start-provision.service

tar -uf rootfs.tar  ./etc/scripts/ || { echo "Adding custom provision scripts to rootfs failed"; exit 1; }
tar -uf rootfs.tar  ./etc/systemd/system/start-provision.service || { echo "Adding emt-s provision service scripts to rootfs failed"; exit 1; }
tar -uf rootfs.tar ./etc/systemd/system/default.target.wants/start-provision.service || { echo "Enable emt-s provision service scripts to rootfs failed"; exit 1; }
# Bundle yq binary if it was downloaded successfully
if [ -f ./usr/bin/yq ]; then
    tar -uf rootfs.tar ./usr/bin/yq || { echo "Adding yq to rootfs failed"; exit 1; }
    echo "yq binary added to rootfs"
fi

gzip -c rootfs.tar > ../rootfs.tar.gz
popd || exit

# Remove the rootfs-tmp content
rm -r initramfs_extract/rootfs-tmp/*

pushd initramfs_extract/ || exit
sudo tar -xzf rootfs.tar.gz > /dev/null 2>&1
find . |sudo cpio -o -H newc | gzip -9 > ../initramfs-x86_64 || { echo "Failed to create initramfs with custom scripts"; exit 1; }
popd || exit
sudo rm -rf initramfs_extract

echo "Successfully injected the custom provision scripts to initramfs"
