#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# nw_custom_service.sh

# Load custom network configuration
if [ -f /etc/cloud/custom_network.conf ]; then
    # shellcheck source=/dev/null
    . /etc/cloud/custom_network.conf
fi

while true; do
    BR_IP=$(ip a show dev "$BR_NAME" | grep 'inet ' | grep -v 'scope host' | awk '{print $2}')
    if [ ! -d /sys/class/net/"$BR_NAME" ] || [ -z "$BR_IP" ]; then
        # Run your script here
        echo "No IP address found on $BR_NAME"
        bash /opt/user-apps/scripts/management/network_config.sh /etc/cloud/custom_network.conf  > /etc/cloud/network_config.log 2>&1
    else
        echo "IP address found on $BR_NAME: $BR_IP"
    fi
    sleep 5
done
