#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Ensure the script exits on error and treats unset variables as errors
set -euo pipefail

# Define the temporary extraction directory
temp_dir="installation_scripts/temp_extraction"

# Create the temporary directory if it doesn't exist
mkdir -p "$temp_dir"

# Check if sen-installation-files.tar.gz file exists
if [ -f "installation_scripts/out/sen-installation-files.tar.gz" ]; then
    echo "sen-installation-files.tar.gz found, extracting..."
    tar -xzf installation_scripts/out/sen-installation-files.tar.gz -C "$temp_dir"
else
    echo "sen-installation-files.tar.gz not found, skipping extraction."
fi

# Check for usb-bootable-files.tar.gz
if [ -f "installation_scripts/out/usb-bootable-files.tar.gz" ]; then
    echo "usb-bootable-files.tar.gz found, extracting..."
    tar -xzf installation_scripts/out/usb-bootable-files.tar.gz -C "$temp_dir"
else
    echo "usb-bootable-files.tar.gz not found, skipping extraction."
fi

echo "Extraction completed. Files are located in $temp_dir"