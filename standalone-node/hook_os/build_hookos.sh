#!/usr/bin/env bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -x

source ./config

export HOOK_KERNEL=${HOOK_KERNEL:-5.10}

if [ "$HOOK_KERNEL" == "5.10" ]; then
    #Current validated kernel_point_version is 228
    export KERNEL_POINT_RELEASE_CONFIG=228
fi

BASE_DIR=$PWD
STORE_ALPINE=$PWD/alpine_image/


# set this to `gsed` if on macos
SED_CMD=sed

# CI pipeline expects the below file. But we need to make the build independent of
# CI requirements. This if-else block creates a new file TINKER_ACTIONS_VERSION from
# versions and that is pulled when hook os is getting built.

build_hook() {

    ver=$(cat VERSION)
    # Iterate over the array and print each element
    arrayof_images=($(cat hook-os.yaml | grep -i ".*image:.*:.*$" | awk -F: '{print $2}'))
    for image in "${arrayof_images[@]}"; do
        temp=$(grep -i "/" <<<$image)
        if [ $? -eq 0 ]; then
            # Non harbor Image
            continue
        fi
        $SED_CMD -i "s/$image:latest/$image:$ver/g" hook-os.yaml
    done

    # copy fluent-bit related files
    copy_fluent_bit_files
    echo "starting to build kernel...................................................."

    if [ "$HOOK_KERNEL" == "6.6" ]; then
        if docker image inspect quay.io/tinkerbell/hook-kernel:6.6.52-2f1e89d8 >/dev/null 2>&1; then
            echo "Rebuild of kernel not required, since its already present in docker images"
        else
            pushd kernel/
            echo "Going to remove patches dir if any"
            rm -rf patches-6.6.y
            mkdir patches-6.6.y
            pushd patches-6.6.y
            #download any patches
            popd
            popd

            #hook-default-amd64
            ./build.sh kernel hook-latest-lts-amd64
        fi
    else
        if docker image inspect quay.io/tinkerbell/hook-kernel:5.10.228-e0637f99 >/dev/null 2>&1; then
            echo "Rebuild of kernel not required, since its already present in docker images"
        else
            # i255 igc driver issue fix
            pushd kernel/
            echo "Going to remove patches DIR if any"
            rm -rf patches-5.10.y
            mkdir patches-5.10.y
            pushd patches-5.10.y
            #download the igc i255 driver patch file
            wget https://github.com/intel/linux-intel-lts/commit/170110adbecc1c603baa57246c15d38ef1faa0fa.patch
            echo "Downloading kernel patches done"
            popd
            popd

            #    ./build.sh kernel default
            ./build.sh kernel
        fi
    fi

    #update the hook.yaml file to point to new kernel
    #$SED_CMD -i "s|quay.io/tinkerbell/hook-kernel:5.10.85-d1225df88208e5a732e820a182b75fb35c737bdd|quay.io/tinkerbell/hook-kernel:5.10.85-298651addd526baaf516da71f76997a3e7c8459d|g" hook.yaml

    # get the client_auth files and container before running the hook os build.
    if [ "$HOOK_KERNEL" == "6.6" ]; then
        ./build.sh build hook-latest-lts-amd64
    else
        ./build.sh
    fi

    mkdir -p $STORE_ALPINE

    if [ "$HOOK_KERNEL" == "6.6" ]; then
        mv $PWD/out/hook_latest-lts-x86_64.tar.gz $PWD/out/hook_x86_64.tar.gz
    fi
    cp $PWD/out/hook_x86_64.tar.gz $STORE_ALPINE

    if [ $? -ne 0 ]; then
        echo "Build of HookOS failed!"
        exit 1
    fi

    echo "Build of HookOS succeeded!"
}

main() {

    sudo apt install -y build-essential bison flex

    build_hook

}

main
