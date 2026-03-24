#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# network_config.sh
# This script configures a Linux network bridge with custom settings for edge or server deployments.
# It validates configuration, sets up a bridge interface, and applies sysctl and optional iptables rules.

# Exit on error, unset variable, or failed pipe
set -euo pipefail
trap 'echo "Error at line $LINENO"; exit 1' ERR
# Check if the script is run as root
br_check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "This script must be run as root."
        exit 1
    fi
}

# Check for required dependencies
br_check_dependencies() {
    local cmd
    for cmd in ip sysctl; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            echo "Command '$cmd' is required but not installed. Please install it and try again."
            exit 1
        fi
    done
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

# Load the br_netfilter kernel module if not already loaded
br_modprob_br_netfilter() {
    if ! lsmod | grep -q br_netfilter; then
        echo "Loading br_netfilter module..."
        if ! modprobe br_netfilter; then
            echo "Failed to load br_netfilter module. Please check your system configuration."
            exit 1
        fi
    else
        echo "br_netfilter module is already loaded."
    fi
}

# Parse the custom network configuration file and set bridge variables
br_parse_custom_network_config() {
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
    # Extract netmask from CIDR
    BR_NETMASK="$(echo "$BR_CIDR" | cut -d'/' -f2)"
    if [[ -z "$BR_NETMASK" ]]; then
        echo "Netmask is not set in the configuration file. Defaulting to 24"
        BR_NETMASK=24
    fi
    if [[ -z "${BR_DNS_NAMESERVER:-}" ]]; then
        echo "BR_DNS_NAMESERVER is not set in the configuration file."
        exit 1
    fi
    # Print configuration summary
    echo "Using BRIDGE_CIDR: $BR_CIDR"
    echo "Using START_RANGE: ${BR_START_RANGE:-}"
    echo "Using END_RANGE: ${BR_END_RANGE:-}"
    echo "Using GATEWAY: $BR_GATEWAY"
    echo "Using NETMASK: $BR_NETMASK"
    echo "Using DNS_NAMESERVER: $BR_DNS_NAMESERVER"
}

# Identify physical (PCI) network interfaces and select a secondary interface
br_identify_secondary_interface() {
    local physical_interfaces=""
    local iface
    # Only include interfaces that are PCI devices (physical NICs)
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        if [[ -L "/sys/class/net/$iface/device" ]] && [[ "$(readlink -f "/sys/class/net/$iface/device")" == /sys/devices/pci* ]]; then
            physical_interfaces+=" $iface"
        fi
    done
    physical_interfaces="$(echo "$physical_interfaces" | xargs)" # trim spaces
    if [[ -z "$physical_interfaces" ]]; then
        echo "No physical interfaces found."
        exit 1
    fi
    echo "Physical interfaces found: $physical_interfaces *****"
    IFS=' ' read -r -a interfaces_array <<< "$physical_interfaces"
    echo "Identified interfaces: ${interfaces_array[*]} ****"
    # Find the default route interface
    local default_route
    default_route="$(ip route | awk '/default/ {print $5; exit}')"
    if [[ -z "$default_route" ]]; then
        echo "No default route found. Cannot determine primary interface."
        exit 1
    fi
    # Select the first non-default interface as secondary
    for interface in "${interfaces_array[@]}"; do
        if [[ "$interface" != "$default_route" ]]; then
            secondary_interfaces="$interface"
            break
        fi
    done
    echo "Primary interface: $default_route"
    echo "Secondary interfaces: $secondary_interfaces"
    if [[ -z "$secondary_interfaces" ]]; then
        echo "No secondary interfaces found."
        exit 1
    fi
}

# Create and configure the bridge interface
br_add_bridge() {
    local bridge_name="$1"
    local secondary_interfaces="$2"
    local BR_GATEWAY="$3"
    local BR_NETMASK="$4"
    if ! ip link show "$bridge_name" > /dev/null 2>&1; then
        echo "Creating bridge $bridge_name..."
        ip link add name "$bridge_name" type bridge
    else
        echo "Bridge $bridge_name already exists."
    fi

    if ! bridge link show | grep -q "$secondary_interfaces"; then
      ip link set "$secondary_interfaces" master "$bridge_name"
    fi
    ip addr add "$BR_GATEWAY"/"$BR_NETMASK" dev "$bridge_name"
    ip link set dev "$bridge_name" up
    ip link set dev "$secondary_interfaces" up

}

# Apply sysctl configuration for bridge networking
br_apply_sysctl_config() {
    local bridge_name="$1"
    echo "Configuring sysctl for bridge $bridge_name..."
    grep -q '^net.bridge.bridge-nf-call-iptables' /etc/sysctl.conf || echo "net.bridge.bridge-nf-call-iptables = 0" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-ip6tables = 0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.all.proxy_arp = 1" >> /etc/sysctl.conf
    sysctl -p
}

# Optionally apply custom iptables rules for the bridge
br_apply_custom_iptables_rules() {
    local bridge_name="$1"
    echo "Applying custom iptables rules for bridge $bridge_name..."
    # Uncomment and adjust the following lines as needed:
    #iptables -t nat -A POSTROUTING -o "$bridge_name" -j MASQUERADE
    #iptables -A FORWARD -i "$bridge_name" -j ACCEPT
    #iptables -A FORWARD -o "$bridge_name" -j ACCEPT
}

# Print usage information
br_usage() {
    echo "Usage: $0 <custom_network.conf>"
    echo "Example: $0 custom_network.conf"
}

br_main() {
    # Main script logic
    if [[ $# -eq 1 ]]; then
        # Initialize bridge variables
        BR_NAME=""
        BR_CIDR=""
        BR_DNS_NAMESERVER=""
        BR_GATEWAY=""
        BR_NETMASK=""
        BR_START_RANGE=""
        BR_END_RANGE=""
        secondary_interfaces=""

        # Run checks and configuration steps
        br_check_root
        br_check_dependencies
        br_check_custom_network_config "$1"
        br_modprob_br_netfilter
        br_parse_custom_network_config "$1"
        if [[ -z "$BR_CIDR" ]]; then
            echo "BR_CIDR is not set in the configuration file."
            exit 1
        fi
        br_identify_secondary_interface
        br_add_bridge "$BR_NAME" "$secondary_interfaces" "$BR_GATEWAY" "$BR_NETMASK"
        br_apply_sysctl_config "$BR_NAME"
        br_apply_custom_iptables_rules "$BR_NAME"
    else
        br_usage
    fi
}

br_main "$@"