#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#set -x
LOCAL_OUTPUT_DIR="$(pwd)/remote_logs"
REMOTE_CMDS="cd /etc/cloud/; sudo chmod +x collect-logs.sh; bash collect-logs.sh"
REMOTE_FILE_PATH="/var/log/edge_node_logs/edge_node_logs.tar.gz"

# This Script is to collect the Edgenode logs for debuging

# Usage info for user
usage() {
    echo "Usage: $0 <user-name of the edgenode> <ip address of the edgenode>"
    echo "Example: $0 user 10.49.39.89"
    exit 1
}
# Validate the inputs
if [ "$#" -ne 2 ]; then
    usage
fi
user_name=$1
ip_address=$2

# Validate inputs
if [ -z "$user_name" ] || [ -z "$ip_address" ]; then
    echo "User_name/IP_address details not provided,please provide valid User_name and IP address"
    usage
    # shellcheck disable=SC2317
    exit 1
fi

# Create the directory to store the edge node logs
if [ ! -d "$LOCAL_OUTPUT_DIR" ]; then
    mkdir -p "$LOCAL_OUTPUT_DIR"
fi

# Connect to the remote system and run the collect-logs.sh

echo "Collecting the logs from Edge Node,Please Wait!!"

if ssh -T -o ConnectTimeout=10 "$user_name"@"$ip_address" "bash -c '$REMOTE_CMDS'" >/dev/null 2>&1; then
    echo "All required logs generated!,Now Copying to Local Server,Please wait!!"
    scp "$user_name@$ip_address:$REMOTE_FILE_PATH" "$LOCAL_OUTPUT_DIR/" >/dev/null 2>&1

    if [ -e "${LOCAL_OUTPUT_DIR}/edge_node_logs.tar.gz" ]; then
        echo "Successfully Collected the Edge node logs and save under $LOCAL_OUTPUT_DIR"
        mv "${LOCAL_OUTPUT_DIR}/edge_node_logs.tar.gz" "${LOCAL_OUTPUT_DIR}/$(date +'%Y-%m-%d_%H-%M-%S')-edge_node_logs.tar.gz"
    else
        echo "Failed to collect the Edge node logs,please check and re-run the script!!!"
        exit 1
    fi
else
    echo "Not able to collet the logs,please check the Edgenode up & Running or incorrect user name or ip address!!"
fi
