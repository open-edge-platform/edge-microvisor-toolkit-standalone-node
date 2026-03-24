#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Check if the script is run as root
br_check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "This script must be run as root."
        exit 1
    fi
}

# Check if the custom network configuration file exists and contains required variables
br_check_custom_network_config() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        echo "Configuration file $config_file not found."
        exit 1
    fi
    if ! grep -qE 'BR_NAME|BR_CIDR|BR_START_RANGE|BR_END_RANGE|BR_GATEWAY|BR_DNS_NAMESERVER' "$config_file"; then
        echo "Configuration file $config_file is missing required variables."
        exit 1
    fi
}

# Parse the custom network configuration file and set bridge variables
parse_custom_network_config() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        echo "Configuration file $config_file not found."
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$config_file"
    # Set defaults and print warnings if variables are missing
    if [[ -z "${BR_NAME:-}" ]]; then
        echo "BR_NAME is not set in the configuration file."
        exit 1
    fi
    if ! [[ "$BR_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Invalid bridge name: $BR_NAME. Only alphanumeric characters, underscores, and hyphens are allowed."
        exit 1
    fi
    if [[ -z "${BR_CIDR:-}" ]]; then
        echo "BR_CIDR is not set in the configuration file."
        exit 1
    fi
    if [[ -z "${BR_START_RANGE:-}" ]]; then
        echo "BR_START_RANGE is not set in the configuration file."
        exit 1
    fi
    if [[ -z "${BR_END_RANGE:-}" ]]; then
        echo "BR_END_RANGE is not set in the configuration file."
        exit 1
    fi
    if [[ -z "${BR_GATEWAY:-}" ]]; then
        echo "BR_GATEWAY is not set in the configuration file."
        exit 1
    fi
    if [[ -z "${BR_DNS_NAMESERVER:-}" ]]; then
        echo "BR_DNS_NAMESERVER is not set in the configuration file."
        exit 1
    fi
}

# Check if K3s is installed
check_k3s_installed() {
    if command -v k3s >/dev/null 2>&1 || command -v /var/lib/rancher/k3s/bin/k3s kubectl >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check if NetworkAttachmentDefinition CRD exists
check_nad_crd() {
    if /var/lib/rancher/k3s/bin/k3s kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Apply NetworkAttachmentDefinition
apply_network_attachment_definition() {
    local bridge_name="$1"
    local bridge_cidr="$2"
    local dns_nameserver="$3"
    local range_start="$4"
    local range_end="$5"
    local gateway="$6"
    cat <<EOF | /var/lib/rancher/k3s/bin/k3s kubectl apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: my-bridge-network
  namespace: user-apps
spec:
  config: |
    {
      "cniVersion": "1.0.0",
      "type": "bridge",
      "bridge": "${bridge_name}",
      "ipam": {
        "type": "host-local",
        "ranges": [
          [
            {
              "subnet": "${bridge_cidr}",
              "rangeStart": "${range_start}",
              "rangeEnd": "${range_end}",
              "gateway": "${gateway}"
            }
          ]
        ]
      },
      "dns": {
        "nameservers": ["${dns_nameserver}"]
      }
    }
EOF
    echo "Network Attachment Definition applied for bridge $bridge_name with CIDR $bridge_cidr."
}

# Main logic
main() {
    # Check for required arguments
    if [[ $# -eq 1 ]]; then
        # Initialize bridge variables
        CONF_FILE="$1"
        BR_NAME=""
        BR_CIDR=""
        BR_DNS_NAMESERVER=""
        BR_GATEWAY=""
        BR_START_RANGE=""
        BR_END_RANGE=""

        # setting kubeconfig default location
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        br_check_root
        br_check_custom_network_config "$CONF_FILE"
        parse_custom_network_config "$CONF_FILE"

        # Wait for K3s (or /var/lib/rancher/k3s/bin/k3s kubectl) and NetworkAttachmentDefinition CRD to be available
        retries=0
        max_retries=600   # 10 minute
        until check_k3s_installed && check_nad_crd; do
          retries=$((retries + 1))
          if ((retries > max_retries)); then
            echo "Timeout waiting for K3s or CRD."
            exit 1
          fi
          sleep 5
        done

        # wait for multus pods to exist first
        echo "Waiting for multus pods to be created..."
        retries=0
        max_retries=600  # 10 minute
        until /var/lib/rancher/k3s/bin/k3s kubectl get pods -l app=multus -n kube-system --no-headers 2>/dev/null | grep -q .; do
          retries=$((retries + 1))
          if ((retries > max_retries)); then
            echo "Timeout waiting for multus pods to be created."
            exit 1
          fi
          sleep 5
        done

        # wait for multus pods to be ready
        echo "Waiting for multus pods to be ready..."
        /var/lib/rancher/k3s/bin/k3s kubectl wait --for=condition=Ready pod -l app=multus -n kube-system --timeout=600s

        # Create user-apps namespace if it doesn't exist
        /var/lib/rancher/k3s/bin/k3s kubectl create ns user-apps || echo "Namespace user-apps already exists or failed to create"

        # Create Multus symbolic links after successful NAD application
        sudo ln -sf /etc/cni/net.d/00-multus.conf /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
        sudo ln -sf /opt/cni/bin/multus /var/lib/rancher/k3s/data/cni/multus

        sleep 3
        
        apply_network_attachment_definition \
            "$BR_NAME" \
            "$BR_CIDR" \
            "$BR_DNS_NAMESERVER" \
            "$BR_START_RANGE" \
            "$BR_END_RANGE" \
            "$BR_GATEWAY"

        # Check for sample file, restart k3s if it doesn't exist
        sample_file="/etc/cloud/k3s_restarted.txt"
        if [[ ! -f "$sample_file" ]]; then
            # Create sample file
            touch "$sample_file"
            sudo systemctl restart k3s
        fi
        
        # Disable iptables rules for bridge traffic
        sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
    else
        echo "Usage: $0 <custom_network.conf>"
    fi
}

main "$@"
