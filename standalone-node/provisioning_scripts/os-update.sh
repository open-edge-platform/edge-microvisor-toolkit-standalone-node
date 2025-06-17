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

# Function to exit with an error message
error_exit() {
    echo "Error: $1"
    exit 1
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi


# Temporary directory for downloads
TEMP_DIR="/tmp/microvisor-update"
mkdir -p "$TEMP_DIR"
check_success "Creating temporary directory"

# URL mode
# TO DO: Improvement scripts to use getopts to parse command line arguments.
if [ "$1" == "-u" ]; then
    # Check if the correct number of arguments is provided for URL mode
    # Example usage: ./os-update.sh -u https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt -r 3.0 -v 20250608.2200
    if [ "$#" -ne 6 ]; then
        error_exit "Usage: $0 -u <URL_to_Microvisor_image_base> -r <release> -v <build_version>"
    fi

    # URL mode
    IMAGE_BASE_URL="$2"
    IMG_VER="$4"
    IMAGE_BUILD="$6"

    # Determine the domain and construct the IMAGE_URL accordingly
    if [[ "$IMAGE_BASE_URL" == *"files-rs.edgeorchestration.intel.com"* ]]; then
        IMAGE_URL="${IMAGE_BASE_URL}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
    elif [[ "$IMAGE_BASE_URL" == *"af01p-png.devtools.intel.com"* ]]; then
        IMAGE_URL="${IMAGE_BASE_URL}/${IMG_VER}/${IMAGE_BUILD}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
    else
        error_exit "Unsupported domain in URL: $IMAGE_BASE_URL"
    fi

    echo "Constructed IMAGE URL: $IMAGE_URL"
    # Download the Microvisor image
    IMAGE_PATH="$TEMP_DIR/edge_microvisor_toolkit.raw.gz"
    echo "Downloading microvisor image from $IMAGE_URL..."
    curl -k "$IMAGE_URL" -o "$IMAGE_PATH" || error_exit "Failed to download microvisor image"

    # Construct the SHA URL
    SHA_URL="${IMAGE_URL}.sha256sum"

    # Download the SHA256 checksum file
    SHA_FILE="$TEMP_DIR/edge_microvisor_readonly.sha256sum"
    echo "Downloading SHA256 checksum from $SHA_URL..."
    curl -k "$SHA_URL" -o "$SHA_FILE" || error_exit "Failed to download SHA256 checksum"

    # Extract the SHA256 checksum
    SHA_ID=$(awk '{print $1}' "$SHA_FILE")
    echo "Extracted SHA256 checksum: $SHA_ID"

else
    # Check if the correct number of arguments is provided for direct mode
    # Example usage: ./os-update.sh  -i /path/to/microvisor_image.raw.gz -c /path/to/microvisor_image.sha256sum
    if [ "$#" -ne 4 ]; then
        error_exit "Usage: $0 -i <Direct_path_to_Microvisor_image> -c <Checksum_file>"
    fi

    # Direct path mode
    IMAGE_PATH="$2"
    SHA_FILE="$4"

    # Verify that the image file exists
    if [ ! -f "$IMAGE_PATH" ]; then
        echo "Error: microvisor image file not found at $IMAGE_PATH"
        exit 1
    fi

    # Verify that the SHA file exists
    if [ ! -f "$SHA_FILE" ]; then
        echo "Error: SHA256 checksum file not found at $SHA_FILE"
        exit 1
    fi

    # Extract the SHA256 checksum
    SHA_ID=$(awk '{print $1}' "$SHA_FILE")
    echo "Extracted SHA256 checksum: $SHA_ID"
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
