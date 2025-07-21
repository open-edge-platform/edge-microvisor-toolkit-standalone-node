#!/bin/bash
# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Download the Edge Microvisor Toolkit from open source no-auth file server
# The file server URL is defined in FILE_RS_URL
FILE_RS_URL="https://files-rs.edgeorchestration.intel.com"
EMT_VERSION=3.0
EMT_BUILD_DATE=20250717
EMT_BUILD_NO=0734
EMT_FILE_NAME="edge-readonly-${EMT_VERSION}.${EMT_BUILD_DATE}.${EMT_BUILD_NO}"
EMT_RAW_GZ="${EMT_FILE_NAME}.raw.gz"
EMT_SHA256SUM="${EMT_FILE_NAME}.raw.gz.sha256sum"

curl -k --noproxy "" ${FILE_RS_URL}/files-edge-orch/repository/microvisor/non_rt/${EMT_RAW_GZ} -o edge_microvisor_toolkit.raw.gz
curl -k --noproxy "" ${FILE_RS_URL}/files-edge-orch/repository/microvisor/non_rt/${EMT_SHA256SUM} -o edge_microvisor_toolkit.raw.gz.sha256sum

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
