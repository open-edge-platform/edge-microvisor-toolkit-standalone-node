#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Define the temporary extraction directory
temp_dir="installation_scripts/temp_extraction"
final_dir="installation_scripts/final_release"

# Create the temporary and final directories if they don't exist
mkdir -p "$temp_dir"
mkdir -p "$final_dir"

# Check if sen-installation-files.tar.gz file exists
if [ -f "installation_scripts/out/sen-installation-files.tar.gz" ]; then
    echo "sen-installation-files.tar.gz found, extracting..."
    tar -xzf installation_scripts/out/sen-installation-files.tar.gz -C "$temp_dir"

    # Move specific files to the final directory
    if [ -f "$temp_dir/config-file" ]; then
        mv "$temp_dir/config-file" "$final_dir/"
    fi

    if [ -f "$temp_dir/bootable-usb-prepare.sh" ]; then
        mv "$temp_dir/bootable-usb-prepare.sh" "$final_dir/"
    fi
else
    echo "sen-installation-files.tar.gz not found, skipping extraction."
fi

# Check for usb-bootable-files.tar.gz
if [ -f "installation_scripts/temp_extraction/usb-bootable-files.tar.gz" ]; then
    echo "usb-bootable-files.tar.gz found, extracting..."
    tar -xzf installation_scripts/temp_extraction/usb-bootable-files.tar.gz -C "$final_dir"
else
    echo "usb-bootable-files.tar.gz not found, skipping extraction."
fi

echo "Extraction completed. Files are located in $final_dir"
