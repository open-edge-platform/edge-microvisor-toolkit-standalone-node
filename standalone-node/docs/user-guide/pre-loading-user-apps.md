# Pre-loading User Application artifacts as part of USB installer

Edge Microvisor Toolkit (EMT) Standalone Node enables users to quickly deploy a single-node
cluster based on lightweight Kubernetes. In scenarios such as OEM (Original Equipment Manufacturer)
use cases, users may need to pre-load applications onto the edge node before testing and shipping
it to its final installation site.This capability is especially useful for those who want their
applications to be available and ready for use immediately after installation.

To support these requirements, EMT Standalone Node allows users to include their application artifacts
within the USB installer.

After extracting the standalone node installer, users can find `user-apps` placeholder apps placed in the root of
the directory where installer is extracted. Users can place their application files like container
images, helm charts, VM images in the `user-apps` folder. The artifacts will be automatically copied
to persistent volume on the Edge node at `/opt/user-apps`. User can use the custom `cloud-init` section
available in the configuration file `config-file` to launch the application after the kubernetes cluster has come up.
User has flexibility to manage the artifacts and what they do using the artifacts and the custom
cloud-init configuration. 5G of USB disk space is used for the installer artifacts. Rest of the USB disk
space is available for the user to store the application artifacts.

## User App Folder

This folder allows users to store application artifacts, such as container images and Helm charts.
All files placed here will be copied to the persistent volume on the Edge node at `/opt/user-apps`.

To copy,configure, or launch your applications, use the custom `cloud-init` section available in the configuration file.

- Store your application files in this folder.
- Update the `cloud-init` section as needed to automate deployment.

## Custom Network Configuration Artifacts

## Sample Networking Scripts for Secondary Interface Configuration

This section provides sample scripts for configuring custom secondary network interfaces on your edge node.

### 1. Network Configuration Script

Create a network configuration script (e.g., save as `network_config.sh`).

> **Note**: Ensure the script filename matches the reference in your `cloud-init` configuration.

```bash
#!/bin/bash

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
        modprobe br_netfilter
        if [[ $? -ne 0 ]]; then
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
    for iface in $(ls /sys/class/net); do
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
        if ! bridge link show | grep -q "$secondary_interfaces"; then
          ip link set "$secondary_interfaces" master "$bridge_name"
        fi
        ip addr add "$BR_GATEWAY"/"$BR_NETMASK" dev "$bridge_name"
        ip link set dev "$bridge_name" up
        ip link set dev "$secondary_interfaces" up
    else
        echo "Bridge $bridge_name already exists."
    fi
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
```

### 2. Bridge Network Attachment Definition Script

Create a script to apply bridge networking attachment definitions (e.g., save as `apply_bridge_nad.sh`).

> **Note**: Ensure the script filename matches the reference in your `cloud-init` configuration.

```bash
#!/bin/bash

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
  namespace: default
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
        max_retries=300  # e.g., 5 minutes
        until check_k3s_installed && check_nad_crd; do
          ((retries++))
          if ((retries > max_retries)); then
            echo "Timeout waiting for K3s or CRD."
            exit 1
          fi
          sleep 1
        done

        apply_network_attachment_definition \
            "$BR_NAME" \
            "$BR_CIDR" \
            "$BR_DNS_NAMESERVER" \
            "$BR_START_RANGE" \
            "$BR_END_RANGE" \
            "$BR_GATEWAY"
    else
        echo "Usage: $0 <custom_network.conf>"
    fi
}

main "$@"
```

## Important Notes

1. **Script Storage and Execution**:
   - Save above scripts in the `user-apps` folder
   - Add the execution command in the `runcmd` section of your `cloud-init` configuration
   - For detailed instructions, refer to `desktop-virtualization-cloud-init.md`

2. **Custom Network Configuration**:
   - Define your custom network configuration in the `write_files` section of your `cloud-init` setup
   - See `desktop-virtualization-cloud-init.md` for comprehensive configuration examples and details
