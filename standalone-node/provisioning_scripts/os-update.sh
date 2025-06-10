#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Source the environment variables
source /etc/environment

set -x

# Function to check the last command's exit status
check_success() {
    if [ "$?" -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Check if the correct number of arguments is provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [-u <URL_to_Microvisor_image> <URL_to_SHA_file>] | <Direct_path_to_Microvisor_image> <SHA256_checksum>"
    exit 1
fi

# Temporary directory for downloads
TEMP_DIR="/tmp/microvisor-update"
mkdir -p "$TEMP_DIR"
check_success "Creating temporary directory"

# Determine if URL mode is used
if [ "$1" == "-u" ]; then
    if [ "$#" -ne 3 ]; then
        echo "Usage: $0 -u <URL_to_Microvisor_image> <URL_to_SHA_file>"
        exit 1
    fi

    # URL mode
    IMAGE_URL="$2"
    SHA_ID="$3"

    # Download the Microvisor image
    IMAGE_PATH="$TEMP_DIR/edge_microvisor_toolkit.raw.gz"
    echo "Downloading microvisor image from $IMAGE_URL..."
    curl -k "$IMAGE_URL" -o "$IMAGE_PATH"
    check_success "Downloading microvisor image"

else
    # Direct path mode
    IMAGE_PATH="$1"
    SHA_ID="$2"

    # Verify that the image file exists
    if [ ! -f "$IMAGE_PATH" ]; then
        echo "Error: microvisor image file not found at $IMAGE_PATH"
        exit 1
    fi
fi

# Invoke the os-update-tool.sh script
echo "Initiating OS update..."
/usr/bin/os-update-tool.sh -w -u "$IMAGE_PATH" -s "$SHA_ID"
check_success "Writing OS image"
/usr/bin/os-update-tool.sh -a
check_success "Applying OS image"

# Reboot the system
echo "Rebooting the system..."
reboot
check_success "Rebooting the system"
