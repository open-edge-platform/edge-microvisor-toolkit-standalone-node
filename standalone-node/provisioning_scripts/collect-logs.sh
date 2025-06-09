#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# This script will collect all required logs on edge node

LOG_DIR="/var/log/edge_node_logs"

if [ ! -d $LOG_DIR ]; then
     sudo mkdir -p $LOG_DIR
else
     sudo rm -rf $LOG_DIR/*
fi

# Collect the dmesg logs
sudo journalctl -k | sudo tee $LOG_DIR/dmesg

# Collect the cluster logs
sudo journalctl -u rke2* | sudo tee $LOG_DIR/rke2-logs

# Collect pods info

source /etc/environment && export KUBECONFIG

kubectl get pods -A | sudo tee $LOG_DIR/pods-running-state

kubectl get svc -A  | sudo tee $LOG_DIR/get_svc-log

kubectl describe pods -A | sudo tee $LOG_DIR/describe-pods-log

# Copy all cloud-init logs, system logs to LOGS_DIR
sudo rsync -av --exclude='$LOG_DIR' /var/log/ $LOG_DIR

pushd $LOG_DIR || exit 1

sudo tar -czf edge_node_logs.tar.gz ./*

sudo chmod 755 edge_node_logs.tar.gz

popd || exit 1
