# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

#!/bin/bash

# for basic testing on a coder setup
if grep -q "Ubuntu" /etc/os-release; then
    sudo rke2-killall.sh
    sudo rke2-uninstall.sh
else
    sudo /opt/rke2/bin/rke2-killall.sh
    sudo /opt/rke2/bin/rke2-uninstall.sh
fi
sudo systemctl stop rancher-system-agent.service
sudo systemctl disable rancher-system-agent.service
sudo rm -f /etc/systemd/system/rancher-system-agent.service
sudo rm -f /etc/systemd/system/rancher-system-agent.env
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/rancher-system-agent
sudo rm -rf /etc/rancher/*
sudo rm -rf /var/lib/rancher/*
sudo rm -rf /usr/local/bin/rke2*
