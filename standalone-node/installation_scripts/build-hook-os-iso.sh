#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#set -x

os_filename=""
# Build the hook os with and generate kernel && initramfs file
build-hook-os(){

echo "Started the Hook OS build!!,it will take some time"

pushd ../hook_os/ || return 1


if make build; then
    echo "Hook OS Build Successful"
else
    echo "Hook OS build Failed,Please check!!"
    exit 1
fi
popd > /dev/null || return 1

}

# Download tvm image and store it under out directory
download-tvm(){

pushd ../host_os > /dev/null || return 1

chmod +x download_tmv.sh
if bash download_tmv.sh; then
    echo "Microvisor  Image downloaded successfuly!!"
    os_filename=$(printf "%s\n" *.raw.gz 2>/dev/null | head -n 1)
    mv "$os_filename" ../installation_scripts/
else
    echo "Microvisor Image download failed,please chheck!!!"
    popd || return 1
    exit 1
fi
popd > /dev/null || return 1
}

# Create alpine-iso
create-hook-os-iso(){
#Check hook_x86_64.tar.gz file  present under build directory
if [ ! -e ../hook_os/out/hook_x86_64.tar.gz ]; then
    echo "Looks hook_x86_64.tar.gz not presnet, build the Hook OS first!!"
    exit 1
else
    # Install the required tool
    sudo apt install grub2-common xorriso mtools dosfstools -y > /dev/null
    # Cleanup the files if exist
    if [ -d out ]; then
        rm -rf out
    fi
    mkdir -p out
    cp ../hook_os/out/hook_x86_64.tar.gz out/
    pushd out/ || return 1
    tar -xzf  hook_x86_64.tar.gz

    # Create the ISO structure
    mkdir -p iso/boot/grub
    mkdir -p iso/EFI/BOOT

    cp vmlinuz-x86_64  iso/boot/vmlinuz
    cp initramfs-x86_64 iso/boot/initrd
       
    # Create the grub config file
    cat <<EOF > iso/boot/grub/grub.cfg
        set timeout=0
        set default=0
        set gfxpayload=text
        set gfxmode=text

        menuentry "Alpine Linux" {
	linux /boot/vmlinuz console=tty0 console=ttyS0 ro quite loglevel=7 usbcore.delay_ms=2000 usbcore.autosuspend=-1 modloop=none text
        initrd /boot/initrd
}
EOF
    # Create the bootable iso that support uefi && bios formats

    if grub-mkrescue -o hook-os.iso iso; then
        echo "ISO created successfully under $(pwd)/out"
    else
        echo "ISO creation failed,please check!!"
        popd >/dev/null || return 1
	exit 1
    fi
    popd >/dev/null || return 1
fi

}

# Pack the ISO image,TVM Image,K8* scripts as tar.gz file 
pack-iso-image-k8scripts(){

# Create the tar file for k8 scripts

mv "$os_filename" out/ 
cp bootable-usb-prepare.sh out/
cp config-file out/
cp edgenode-logs-collection.sh out/

# Pack hook-os-iso,tvm image,k8-scripts as tar.gz
pushd out > /dev/null || return 1
checksum_file="checksums.md5"


if {
    md5sum hook-os.iso
    md5sum edge_microvisor_toolkit.raw.gz
    md5sum sen-rke2-package.tar.gz
} >> $checksum_file; then
    echo "Checksum file $checksum_file created successfully in $(pwd)"
else
    echo "Failed to create checksum file, please check!"
    exit 1
fi
tar -czf usb-bootable-files.tar.gz hook-os.iso "$os_filename" sen-rke2-package.tar.gz $checksum_file > /dev/null

if tar -czf usb-bootable-files.tar.gz hook-os.iso "$os_filename" sen-rke2-package.tar.gz $checksum_file > /dev/null; then
    if tar -czf sen-installation-files.tar.gz bootable-usb-prepare.sh config-file usb-bootable-files.tar.gz edgenode-logs-collection.sh; then
        echo ""
	echo ""
	echo ""
	# Delete all other generated files other than sen-installation-files.tar.gz
        find . -mindepth 1 -not -name "sen-installation-files.tar.gz" -delete
        echo "##############################################################################################"
        echo "                                                                                              "
        echo "                                                                                              "
        echo "Standalone Installation files--> sen-installation-files.tar.gz created successfuly, under $(pwd)"
        echo "                                                                                              "
        echo "                                                                                              "
        echo "###############################################################################################"
    else
	echo "Failed to create Standalone Installation files,Please check!!!"
	popd || return 1
	exit 1
    fi
else
    echo "usb-bootable-files.tar.gz not created,please checke!!!"
    popd || return 1
    exit 1
fi
popd || return 1

}

# Download the K8 charts and images
download-charts-and-images(){

echo "Downloading K8 charts and images,please wait!!!"
pushd ../cluster_installers > /dev/null || return 1
chmod +x download_charts_and_images.sh 
chmod +x build_package.sh 


if ! bash download_charts_and_images.sh > /dev/null; then
    echo "Downloding K8 charts and images failed,please check!!!"
    popd || return 1
    exit 1
else
    echo "Downloding K8 charts and images successful"
fi
# Build packages

if ! bash build_package.sh > /dev/null; then
    echo "Build pkgs failed,please check!!!"
    popd || return 1
    exit 1
else
    echo "Build pkgs successful"
fi
echo "Disk space usage after building rke2 packages:"
df -h
echo "Current directory: $(pwd)"
echo "File exists: $(ls sen-rke2-package.tar.gz)"
echo "Target directory exists: $(ls ../installation_scripts/out/)"
if [ ! -f sen-rke2-package.tar.gz ]; then
    echo "File sen-rke2-package.tar.gz does not exist, please check!"
    popd || return 1
    exit 1
fi
if [ ! -d ../installation_scripts/out/ ]; then
    echo "Directory ../installation_scripts/out/ does not exist, please check!"
    popd || return 1
    exit 1
fi
echo "Before copying sen rke2 packages"
if ! cp  sen-rke2-package.tar.gz  ../installation_scripts/out/; then
    echo "Build pkgs && Images copy failed to out directory, please check!!"
    popd || return 1
    exit 1
else
    echo "Build pkgs && Images successfuly copied"
fi
echo "After copying sen rke2 packages"
popd || return 1
}

main(){

echo "Main func: Disk space usage before build:"
df -h
build-hook-os

download-tvm

create-hook-os-iso

download-charts-and-images

pack-iso-image-k8scripts

}

######@main#####
main
