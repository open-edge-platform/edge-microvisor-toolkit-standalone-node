#!/bin/bash
# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Download the tiber Microvisor from open source no-auth file server
# The file server URL is defined in FILE_RS_URL
FILE_RS_URL="https://af01p-png.devtools.intel.com"
TMV_VERSION=3.0
TMV_BUILD_DATE=20250305
TMV_BUILD_NO=2205
TMV_FILE_NAME="tiber-readonly-${TMV_VERSION}.${TMV_BUILD_DATE}.${TMV_BUILD_NO}-signed"
TMV_RAW_GZ="${TMV_FILE_NAME}.raw.gz"
TMV_DER="${TMV_FILE_NAME}.der"
TMV_SHA256SUM="${TMV_FILE_NAME}.raw.gz.sha256sum"

wget --no-proxy --no-check-certificate ${FILE_RS_URL}/artifactory/tiberos-png-local/non-rt/${TMV_VERSION}/${TMV_BUILD_DATE}.${TMV_BUILD_NO}/${TMV_RAW_GZ} -O tiber_microvisor.raw.gz
wget --no-proxy --no-check-certificate ${FILE_RS_URL}/artifactory/tiberos-png-local/non-rt/${TMV_VERSION}/${TMV_BUILD_DATE}.${TMV_BUILD_NO}/${TMV_DER} -O tiber_microvisor.der
wget --no-proxy --no-check-certificate ${FILE_RS_URL}/artifactory/tiberos-png-local/non-rt/${TMV_VERSION}/${TMV_BUILD_DATE}.${TMV_BUILD_NO}/${TMV_SHA256SUM} -O tiber_microvisor.raw.gz.sha256sum

# Verify the SHA256 checksum
echo "Verifying SHA256 checksum..."
EXPECTED_CHECKSUM=$(awk '{print $1}' tiber_microvisor.raw.gz.sha256sum)
ACTUAL_CHECKSUM=$(sha256sum tiber_microvisor.raw.gz | awk '{print $1}')

if [ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]; then
    echo "SHA256 checksum verification passed."
else
    echo "SHA256 checksum verification failed!" >&2
    exit 1
fi
