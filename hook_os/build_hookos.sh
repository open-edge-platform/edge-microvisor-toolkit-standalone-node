#!/usr/bin/env bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -x
# shellcheck source=installation_scripts/config-file
source ./config

export HOOK_KERNEL=${HOOK_KERNEL:-5.10}

if [ "$HOOK_KERNEL" == "5.10" ]; then
    #Current validated kernel_point_version is 228
    export KERNEL_POINT_RELEASE_CONFIG=228
fi
# shellcheck disable=SC2034
BASE_DIR=$PWD

# set this to `gsed` if on macos
# shellcheck disable=SC2034
SED_CMD="sed"

# CI pipeline expects the below file. But we need to make the build independent of
# CI requirements. This if-else block creates a new file TINKER_ACTIONS_VERSION from
# versions and that is pulled when hook os is getting built.

build_hook() {
    # shellcheck disable=SC2034
    ver=$(cat VERSION)
    # Iterate over the array and print each element
    # shellcheck disable=SC2002
    # shellcheck disable=SC2207
    arrayof_images=($(cat hook-os.yaml | grep -i ".*image:.*:.*$" | awk -F: '{print $2}'))
    for image in "${arrayof_images[@]}"; do
        # shellcheck disable=SC2034
        if temp=$(grep -i "/" <<<"$image"); then
            # Non harbor Image
            continue
        fi
    done

    echo "starting to build kernel...................................................."

    if [ "$HOOK_KERNEL" == "6.6" ]; then
        if docker image inspect quay.io/tinkerbell/hook-kernel:6.6.52-2f1e89d8 >/dev/null 2>&1; then
            echo "Rebuild of kernel not required, since its already present in docker images"
        else
            pushd kernel/ ||return 1
            echo "Going to remove patches dir if any"
            rm -rf patches-6.6.y
            mkdir patches-6.6.y
            pushd patches-6.6.y || return 1
            #download any patches
            popd || return 1
            popd || return 1

            #hook-default-amd64
            ./build.sh kernel hook-latest-lts-amd64
        fi
    else
            # i255 igc driver issue fix
            pushd kernel/ || return 1
            echo "Going to remove patches DIR if any"
            rm -rf patches-5.10.y
            mkdir patches-5.10.y
            pushd patches-5.10.y || return 1
            #download the igc i255 driver patch file
            wget https://github.com/intel/linux-intel-lts/commit/170110adbecc1c603baa57246c15d38ef1faa0fa.patch
            echo "Downloading kernel patches done"
            popd || return 1
            popd || return 1

            #    ./build.sh kernel default
            ./build.sh kernel
    fi

    # get the client_auth files and container before running the hook os build.
    if [ "$HOOK_KERNEL" == "6.6" ]; then
        ./build.sh build hook-latest-lts-amd64
    else
        ./build.sh
    fi

    if [ "$HOOK_KERNEL" == "6.6" ]; then
        mv "$PWD"/out/hook_latest-lts-x86_64.tar.gz "$PWD"/out/hook_x86_64.tar.gz
    fi
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "Build of HookOS failed!"
        exit 1
    fi

    echo "Build of HookOS succeeded!"
}

build_debian_img()
{
# Create the debian image for os installation
pushd images/hook-debian/ || return 1

if ! docker build  -t debian:12.10 .; then
    echo "Debian image generation failed"
    popd > /dev/null || return 1
    exit 1
else
    echo "Debian image build success"
fi
popd || return 1

}


main() {

    sudo apt install -y build-essential bison flex
    sudo apt install -y grub2-common xorriso mtools dosfstools

    build_debian_img

    build_hook
}

main
