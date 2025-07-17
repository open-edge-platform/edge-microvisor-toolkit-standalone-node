#!/bin/bash
# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Download the Edge Microvisor Toolkit from open source no-auth file server
# The file server URL is defined in FILE_RS_URL
FILE_RS_URL="https://files-rs.edgeorchestration.intel.com"
EMT_VERSION=3.0
EMT_BUILD_DATE=20250711
EMT_BUILD_NO=0415
EMT_FILE_NAME="edge-readonly-${EMT_VERSION}.${EMT_BUILD_DATE}.${EMT_BUILD_NO}"
EMT_RAW_GZ="${EMT_FILE_NAME}.raw.gz"
EMT_SHA256SUM="${EMT_FILE_NAME}.raw.gz.sha256sum"

wget --no-proxy https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250717.0734/edge-readonly-3.0.20250717.0734.raw.gz -O edge_microvisor_toolkit.raw.gz
wget --no-proxy https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250717.0734/edge-readonly-3.0.20250717.0734.raw.gz.sha256sum -O edge_microvisor_toolkit.raw.gz.sha256sum

# Verify the SHA256 checksum
echo "Verifying SHA256 checksum..."
EXPECTED_CHECKSUM=$(awk '{print $1}' edge_microvisor_toolkit.raw.gz.sha256sum)
ACTUAL_CHECKSUM=$(sha256sum edge_microvisor_toolkit.raw.gz | awk '{print $1}')

if [ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]; then
    echo "SHA256 checksum verification passed."
else
    echo "SHA256 checksum verification failed!" >&2
    exit 1
fi
