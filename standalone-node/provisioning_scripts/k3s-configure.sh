#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Start the cluster install scripts only once
if [ ! -f "/var/lib/rancher/k3s_status" ]; then
    cd /etc/cloud/ || exit

    chmod +x sen-k3s-installer.sh

    bash sen-k3s-installer.sh
else
    echo "k3s is already installed and running. Skipping installation." | sudo tee /var/log/cluster-init.log | sudo tee /dev/tty1
    cd /etc/cloud/ || exit
    chmod +x k3s-setup-post-reboot.sh
    bash k3s-setup-post-reboot.sh
fi
