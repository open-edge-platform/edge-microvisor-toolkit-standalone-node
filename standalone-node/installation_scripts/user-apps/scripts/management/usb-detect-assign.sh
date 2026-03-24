#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail  # Exit on any error, undefined variables, and pipe failures

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root."
    echo "Please run with sudo: sudo $0 $*"
    exit 1
fi

# Default configuration
NAMESPACE="user-apps"
DEFAULT_FILE_LOCATION="/opt/user-apps/helm_charts/sidecar/"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Operation modes
UPDATE_CONFIGMAP=false
UPDATE_FILES=false
FILE_LOCATION=""

# USB device assignments
USB3_BUS=""
USB3_PORT=""
KEYBOARD_BUS=""
KEYBOARD_PORT=""
MOUSE_BUS=""
MOUSE_PORT=""
TOUCHSCREEN_BUS=""
TOUCHSCREEN_PORT=""
# Array to store all USB 3.0 device info
USB3_DEVICES=()

# Global variable for kubectl command
KUBECTL_CMD=""

# Function to detect the appropriate kubectl command (inspired by old-context.sh)
detect_kubectl_command() {
    if command -v /var/lib/rancher/k3s/bin/k3s >/dev/null 2>&1 && /var/lib/rancher/k3s/bin/k3s kubectl version --client >/dev/null 2>&1; then
        KUBECTL_CMD="/var/lib/rancher/k3s/bin/k3s kubectl"
        log "Found working kubectl command: 'k3s kubectl'"
    elif command -v kubectl >/dev/null 2>&1; then
        KUBECTL_CMD="kubectl"
        log "Found working kubectl command: 'kubectl'"
    else
        KUBECTL_CMD=""
        error "Neither '/var/lib/rancher/k3s/bin/k3s kubectl' nor 'kubectl' found or working"
    fi
}

# Function to execute kubectl commands with auto-detection
kubectl_exec() {
    if [[ -z "$KUBECTL_CMD" ]]; then
        detect_kubectl_command
    fi
    $KUBECTL_CMD "$@"
}

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -c, --configmap         Update ConfigMaps and restart VMs
    -f, --files [LOCATION]  Update ConfigMap YAML files at location (default: $DEFAULT_FILE_LOCATION)
    -a, --all [LOCATION]    Do both operations (equivalent to -c -f)
    -n, --namespace NAME    Kubernetes namespace (default: $NAMESPACE)
    -h, --help             Show this help message

EXAMPLES:
    $0 -c                                    # Update ConfigMaps and restart VMs
    $0 -f                                    # Update YAML files in default location
    $0 -f /custom/path/                      # Update YAML files in custom location
    $0 -a                                    # Update both ConfigMaps and files
    $0 -a /custom/path/                      # Update both with custom file location
    $0 -n my-namespace -c                    # Use custom namespace

DESCRIPTION:
    This script detects USB devices and assigns them based on requirements:
    - First USB 3.0 device → Ubuntu VM (for high-speed storage/devices)
    - Keyboard, mouse, and touchscreen devices → Windows VM
    
    ConfigMaps are identified by labels:
    - Windows: "os: win11" or "os: windows"
    - Ubuntu: "os: ubuntu22" or "os: ubuntu"

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--configmap)
                UPDATE_CONFIGMAP=true
                shift
                ;;
            -f|--files)
                UPDATE_FILES=true
                if [[ $# -gt 1 ]] && [[ $2 != -* ]]; then
                    FILE_LOCATION="$2"
                    shift
                else
                    FILE_LOCATION="$DEFAULT_FILE_LOCATION"
                fi
                shift
                ;;
            -a|--all)
                UPDATE_CONFIGMAP=true
                UPDATE_FILES=true
                if [[ $# -gt 1 ]] && [[ $2 != -* ]]; then
                    FILE_LOCATION="$2"
                    shift
                else
                    FILE_LOCATION="$DEFAULT_FILE_LOCATION"
                fi
                shift
                ;;
            -n|--namespace)
                if [[ $# -gt 1 ]] && [[ $2 != -* ]]; then
                    NAMESPACE="$2"
                    shift
                else
                    error "Namespace option requires a value"
                fi
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use -h for help."
                ;;
        esac
    done

    # Validate that at least one operation is selected
    if [[ "$UPDATE_CONFIGMAP" == false ]] && [[ "$UPDATE_FILES" == false ]]; then
        error "No operation specified. Use -c for ConfigMaps, -f for files, or -a for both. Use -h for help."
    fi

    # Set default file location if not specified
    if [[ "$UPDATE_FILES" == true ]] && [[ -z "$FILE_LOCATION" ]]; then
        FILE_LOCATION="$DEFAULT_FILE_LOCATION"
    fi

    info "Operation mode: ConfigMaps=$UPDATE_CONFIGMAP, Files=$UPDATE_FILES, Namespace=$NAMESPACE"
    if [[ "$UPDATE_FILES" == true ]]; then
        info "File location: $FILE_LOCATION"
    fi
}

# Function to get USB port path for hub-connected devices
get_usb_port_path() {
    local bus="$1"
    local dev="$2"
    local lsusb_tree
    
    # Remove leading zeros for matching
    local dev_num
    dev_num=${dev##0}
    
    lsusb_tree=$(lsusb -t 2>/dev/null)
    
    # Look for the device in lsusb -t output
    local device_line
    device_line=$(echo "$lsusb_tree" | grep "Dev $dev_num")
    
    if [[ -n "$device_line" ]]; then
        # Extract port path from the device line
        if [[ $device_line =~ Port\ ([0-9]+(\.[0-9]+)*) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    
    # Fallback: just return device number
    echo "$dev_num"
}

# Enhanced USB device detection with requirement-based assignment
# This function now supports both Ubuntu and EMTD VMs (assigns first USB 3.0 device to either)
detect_usb_devices() {
    log "Detecting USB devices with requirement-based assignment..."
    
    local lsusb_output
    lsusb_output=$(lsusb 2>/dev/null || echo "")
    local lsusb_tree
    lsusb_tree=$(lsusb -t 2>/dev/null || echo "")
    
    if [[ -z "$lsusb_output" ]]; then
        error "Failed to get lsusb output"
    fi
    
    info "USB Detection Strategy:"
    info "1. Find first USB 3.0 device for Ubuntu"
    info "2. Find keyboard, mouse, and touchscreen devices for Windows"
    info "3. Handle hub-connected devices appropriately"
    
    # Arrays to store found devices
    local usb3_devices=()
    local hid_devices=()
    local touchscreen_devices=()
    local all_devices=()
    
    # Parse lsusb output and categorize devices
    while IFS= read -r line; do
        if [[ $line =~ Bus\ ([0-9]+)\ Device\ ([0-9]+):.*ID\ ([0-9a-f]{4}:[0-9a-f]{4})\ (.+) ]]; then
            local bus="${BASH_REMATCH[1]}"
            local dev="${BASH_REMATCH[2]}"
            local id="${BASH_REMATCH[3]}"
            local desc="${BASH_REMATCH[4]}"
            local desc_lower
            desc_lower=$(echo "$desc" | tr '[:upper:]' '[:lower:]')
            
            # Skip root hubs
            if [[ $desc_lower =~ "root hub" ]]; then
                continue
            fi
            # Skip USB external hubs
            if [[ $desc_lower =~ "hub" ]]; then
                continue
            fi
            
            all_devices+=("$bus:$dev:$id:$desc")
            
            # Check if device is on USB 3.0 bus (look for 5000M, 10000M, 20000M speeds)
            local device_speed=""
            local device_tree_line
            device_tree_line=$(echo "$lsusb_tree" | grep "Bus $bus" -A 20 | grep "Dev $dev")
            if [[ $device_tree_line =~ ([0-9]+M) ]]; then
                device_speed="${BASH_REMATCH[1]}"
            fi
            
            # USB 3.0 devices (5000M and above speeds)
            if [[ $device_speed =~ ^[5-9][0-9]{3}M|^[1-9][0-9]{4}M ]]; then
                usb3_devices+=("$bus:$dev:$id:$desc:$device_speed")
                info "Found USB 3.0 device: $desc (Bus $bus, Device $dev, Speed $device_speed)"
            fi
            
            # HID devices (keyboard, mouse, etc.)
            if [[ $desc_lower =~ "human interface"|"hid"|"keyboard"|"mouse"|"raritan.*kvm"|"d2cim-vusb" ]]; then
                hid_devices+=("$bus:$dev:$id:$desc")
                info "Found HID device: $desc (Bus $bus, Device $dev)"
            fi
            
            # Touchscreen devices (detect by vendor:product ID or description)
            if [[ $id == "222a:0001" || $desc_lower =~ "multi-touch"|"touchscreen"|"touch screen"|"ili technology" ]]; then
                touchscreen_devices+=("$bus:$dev:$id:$desc")
                info "Found touchscreen device: $desc (Bus $bus, Device $dev)"
            fi
        fi
    done <<< "$lsusb_output"
    
    # Assignment Logic
    
    # 1. Assign all USB 3.0 devices (directly connected or via hub) to Ubuntu
    # Only enumerate USB 3.0 devices connected to bus 2, not bus 1
    if [[ ${#usb3_devices[@]} -gt 0 ]]; then
        log "Filtering USB 3.0 devices: only Bus 2 devices will be assigned to Ubuntu"
        
        # Store only USB 3.0 devices that are on bus 2
        local bus2_usb3_count=0
        for usb3_device in "${usb3_devices[@]}"; do
            IFS=':' read -r bus dev id desc speed <<< "$usb3_device"
            
            # Skip devices not on bus 2
            if [[ "$bus" != "002" ]] && [[ "$bus" != "02" ]] && [[ "$bus" != "2" ]]; then
                info "Skipping USB 3.0 device on Bus $bus (not Bus 2): $desc"
                continue
            fi
            
            local port
            port=$(get_usb_port_path "$bus" "$dev")
            
            # Store device info in array
            USB3_DEVICES+=("$bus:$dev:$port:$desc")
            bus2_usb3_count=$((bus2_usb3_count + 1))
            
            log "Assigned USB 3.0 device to Ubuntu: $desc (Bus $bus, Device $dev, Port $port, Speed $speed)"
        done
        
        if [[ $bus2_usb3_count -eq 0 ]]; then
            warn "No USB 3.0 devices found on Bus 2! Ubuntu will not have USB 3.0 device assigned."
            USB3_DEVICES=()
        else
            log "Found ${#USB3_DEVICES[@]} USB 3.0 device(s) on Bus 2 to assign to Ubuntu"
            # Keep the first device in the original variables for backward compatibility
            IFS=':' read -r USB3_BUS USB3_DEV USB3_PORT _ <<< "${USB3_DEVICES[0]}"
        fi
    else
        warn "No USB 3.0 devices found! Ubuntu will not have USB 3.0 device assigned."
        USB3_DEVICES=()
    fi
    
    # 2. Assign keyboard, mouse, and touchscreen devices to Windows
    local hid_assigned_count=0
    for hid_device in "${hid_devices[@]}"; do
        if [[ $hid_assigned_count -ge 2 ]]; then
            break
        fi
        
        IFS=':' read -r hid_bus hid_dev _ hid_desc <<< "$hid_device"
        
        # Skip if this device is already assigned to Ubuntu (USB 3.0)
        if [[ "$hid_bus" == "$USB3_BUS" && "$hid_dev" == "$USB3_DEV" ]]; then
            info "Skipping HID device (already assigned to Ubuntu): $hid_desc"
            continue
        fi
        
        local hid_port
        hid_port=$(get_usb_port_path "$hid_bus" "$hid_dev")
        
        if [[ $hid_assigned_count -eq 0 ]]; then
            KEYBOARD_BUS="$hid_bus"
            KEYBOARD_DEV="$hid_dev"
            KEYBOARD_PORT="$hid_port"
            log "✓ Assigned keyboard device to Windows: $hid_desc (Bus $hid_bus, Device $hid_dev, Port $hid_port)"
        elif [[ $hid_assigned_count -eq 1 ]]; then
            MOUSE_BUS="$hid_bus"
            MOUSE_DEV="$hid_dev"
            MOUSE_PORT="$hid_port"
            log "✓ Assigned mouse device to Windows: $hid_desc (Bus $hid_bus, Device $hid_dev, Port $hid_port)"
        fi
        
        hid_assigned_count=$((hid_assigned_count + 1))
    done
    
    # 3. Assign touchscreen device to Windows
    local touchscreen_assigned=false
    for touchscreen_device in "${touchscreen_devices[@]}"; do
        IFS=':' read -r ts_bus ts_dev _ ts_desc <<< "$touchscreen_device"
        
        # Skip if this device is already assigned to Ubuntu (USB 3.0)
        if [[ "$ts_bus" == "$USB3_BUS" && "$ts_dev" == "$USB3_DEV" ]]; then
            info "Skipping touchscreen device (already assigned to Ubuntu): $ts_desc"
            continue
        fi
        
        # Skip if this device is already assigned as keyboard or mouse
        if [[ ("$ts_bus" == "$KEYBOARD_BUS" && "$ts_dev" == "$KEYBOARD_DEV") ||
              ("$ts_bus" == "$MOUSE_BUS" && "$ts_dev" == "$MOUSE_DEV") ]]; then
            info "Skipping touchscreen device (already assigned as keyboard/mouse): $ts_desc"
            continue
        fi
        
        local ts_port
        ts_port=$(get_usb_port_path "$ts_bus" "$ts_dev")
        TOUCHSCREEN_BUS="$ts_bus"
        TOUCHSCREEN_DEV="$ts_dev"
        TOUCHSCREEN_PORT="$ts_port"
        log "✓ Assigned touchscreen device to Windows: $ts_desc (Bus $ts_bus, Device $ts_dev, Port $ts_port)"
        touchscreen_assigned=true
        break
    done
    
    if [[ "$touchscreen_assigned" != true ]]; then
        warn "No touchscreen devices found for Windows assignment"
    fi
    
    # Fallback assignment if not enough HID devices found
    if [[ $hid_assigned_count -lt 2 ]]; then
        warn "Only found $hid_assigned_count HID devices, assigning from available devices..."
        
        # Use any available non-USB3.0 devices as fallback
        for device in "${all_devices[@]}"; do
            if [[ $hid_assigned_count -ge 2 ]]; then
                break
            fi
            
            IFS=':' read -r fallback_bus fallback_dev _ fallback_desc <<< "$device"
            
            # Skip if already assigned to Ubuntu
            if [[ "$fallback_bus" == "$USB3_BUS" && "$fallback_dev" == "$USB3_DEV" ]]; then
                continue
            fi
            
            # Skip if already assigned as keyboard or mouse
            if [[ ("$fallback_bus" == "$KEYBOARD_BUS" && "$fallback_dev" == "$KEYBOARD_DEV") ||
                  ("$fallback_bus" == "$MOUSE_BUS" && "$fallback_dev" == "$MOUSE_DEV") ]]; then
                continue
            fi
            
            # Skip if already assigned as touchscreen
            if [[ "$fallback_bus" == "$TOUCHSCREEN_BUS" && "$fallback_dev" == "$TOUCHSCREEN_DEV" ]]; then
                continue
            fi
            
            local fallback_port
            fallback_port=$(get_usb_port_path "$fallback_bus" "$fallback_dev")
            
            if [[ $hid_assigned_count -eq 0 && -z "$KEYBOARD_BUS" ]]; then
                KEYBOARD_BUS="$fallback_bus"
                KEYBOARD_DEV="$fallback_dev"
                KEYBOARD_PORT="$fallback_port"
                log "✓ Fallback keyboard assignment: $fallback_desc (Bus $fallback_bus, Device $fallback_dev, Port $fallback_port)"
                hid_assigned_count=$((hid_assigned_count + 1))
            elif [[ $hid_assigned_count -eq 1 && -z "$MOUSE_BUS" ]]; then
                MOUSE_BUS="$fallback_bus"
                MOUSE_DEV="$fallback_dev"
                MOUSE_PORT="$fallback_port"
                log "✓ Fallback mouse assignment: $fallback_desc (Bus $fallback_bus, Device $fallback_dev, Port $fallback_port)"
                hid_assigned_count=$((hid_assigned_count + 1))
            fi
        done
    fi
    
    # Format bus and device numbers (remove leading zeros for QEMU)
    if [[ -n "${USB3_BUS:-}" ]]; then
        USB3_BUS=${USB3_BUS##+(0)}
    fi
    if [[ -n "${USB3_DEV:-}" ]]; then
        USB3_DEV=${USB3_DEV##+(0)}
    fi
    if [[ -n "${KEYBOARD_BUS:-}" ]]; then
        KEYBOARD_BUS=${KEYBOARD_BUS##+(0)}
    fi
    if [[ -n "${KEYBOARD_DEV:-}" ]]; then
        KEYBOARD_DEV=${KEYBOARD_DEV##+(0)}
    fi
    if [[ -n "${MOUSE_BUS:-}" ]]; then
        MOUSE_BUS=${MOUSE_BUS##+(0)}
    fi
    if [[ -n "${MOUSE_DEV:-}" ]]; then
        MOUSE_DEV=${MOUSE_DEV##+(0)}
    fi
    if [[ -n "${TOUCHSCREEN_BUS:-}" ]]; then
        TOUCHSCREEN_BUS=${TOUCHSCREEN_BUS##+(0)}
    fi
    if [[ -n "${TOUCHSCREEN_DEV:-}" ]]; then
        TOUCHSCREEN_DEV=${TOUCHSCREEN_DEV##+(0)}
    fi
    
    log "Final USB Device Assignment Summary:"
    # Note: The USB 3.0 assignment logic below applies to both Ubuntu and EMTD VMs.
    # If an EMTD VM is present, it will use the same USB 3.0 device as Ubuntu.
    if [[ -n "$USB3_BUS" ]]; then
        log "  Ubuntu/EMTD (USB 3.0): Bus $USB3_BUS, Port $USB3_PORT"
    else
        warn "  Ubuntu/EMTD: No USB 3.0 device assigned"
    fi
    
    if [[ -n "$KEYBOARD_BUS" ]]; then
        log "  Windows Keyboard: Bus $KEYBOARD_BUS, Port $KEYBOARD_PORT"
    else
        warn "  Windows: No keyboard device assigned"
    fi
    
    if [[ -n "$MOUSE_BUS" ]]; then
        log "  Windows Mouse: Bus $MOUSE_BUS, Port $MOUSE_PORT"
    else
        warn "  Windows: No mouse device assigned"
    fi
    
    if [[ -n "$TOUCHSCREEN_BUS" ]]; then
        log "  Windows Touchscreen: Bus $TOUCHSCREEN_BUS, Port $TOUCHSCREEN_PORT"
    else
        warn "  Windows: No touchscreen device assigned"
    fi
}

# Function to build QEMU USB arguments based on port path
build_qemu_args() {
    local bus="$1"
    local port="$2"
    local vm_type="$3"  # Added VM type parameter
    
    if [[ -z "$bus" || -z "$port" ]]; then
        return 1
    fi
    
    # Build the base USB host argument
    local base_args="usb-host,hostbus=${bus},hostaddr=${port}"
    
    # Add bus controller for Ubuntu and EMTD VMs
    if [[ "$vm_type" == "ubuntu" || "$vm_type" == "emtd" ]]; then
        base_args="${base_args},bus=usb-controller.0"
    fi
    
    echo "<qemu:arg value='-device'/> <qemu:arg value='${base_args}'/>"
}

# Function to build USB arguments for ConfigMaps
# Builds the USB passthrough arguments for a given VM type (ubuntu, emtd, windows)
# vm_type: "ubuntu", "emtd", or "windows"
# For ubuntu/emtd: assign first USB 3.0 device
# For windows: assign keyboard, mouse, touchscreen devices, avoiding duplicates
build_usb_args_for_vm() {
    local vm_type="$1"  # "ubuntu", "emtd", or "windows"
    local args=""
    case "$vm_type" in
        "ubuntu"|"emtd")  # EMTD support added
            # Iterate through all USB 3.0 devices and build arguments
            if [[ ${#USB3_DEVICES[@]} -gt 0 ]]; then
                local usb3_args=()
                for usb3_device in "${USB3_DEVICES[@]}"; do
                    IFS=':' read -r bus dev port desc <<< "$usb3_device"
                    local device_args
                    device_args=$(build_qemu_args "$bus" "$port" "$vm_type")
                    if [[ -n "$device_args" ]]; then
                        usb3_args+=("$device_args")
                    fi
                done
                if [[ ${#usb3_args[@]} -gt 0 ]]; then
                    args=$(printf "%s " "${usb3_args[@]}")
                    args=${args% }  # Remove trailing space
                fi
            fi
            ;;
        "windows")
            local kb_args=""
            local mouse_args=""
            local touchscreen_args=""
            if [[ -n "$KEYBOARD_BUS" && -n "$KEYBOARD_PORT" ]]; then
                kb_args=$(build_qemu_args "$KEYBOARD_BUS" "$KEYBOARD_PORT" "$vm_type")
            fi
            if [[ -n "$MOUSE_BUS" && -n "$MOUSE_PORT" ]]; then
                # Avoid duplicate if keyboard and mouse are the same device
                if [[ "$KEYBOARD_BUS" != "$MOUSE_BUS" || "$KEYBOARD_PORT" != "$MOUSE_PORT" ]]; then
                    mouse_args=$(build_qemu_args "$MOUSE_BUS" "$MOUSE_PORT" "$vm_type")
                fi
            fi
            if [[ -n "$TOUCHSCREEN_BUS" && -n "$TOUCHSCREEN_PORT" ]]; then
                # Avoid duplicate if touchscreen is the same as keyboard or mouse
                if [[ ("$TOUCHSCREEN_BUS" != "$KEYBOARD_BUS" || "$TOUCHSCREEN_PORT" != "$KEYBOARD_PORT") &&
                      ("$TOUCHSCREEN_BUS" != "$MOUSE_BUS" || "$TOUCHSCREEN_PORT" != "$MOUSE_PORT") ]]; then
                    touchscreen_args=$(build_qemu_args "$TOUCHSCREEN_BUS" "$TOUCHSCREEN_PORT" "$vm_type")
                fi
            fi
            # Combine all available args
            local all_args=()
            [[ -n "$kb_args" ]] && all_args+=("$kb_args")
            [[ -n "$mouse_args" ]] && all_args+=("$mouse_args")
            [[ -n "$touchscreen_args" ]] && all_args+=("$touchscreen_args")
            if [[ ${#all_args[@]} -gt 0 ]]; then
                args=$(printf "%s " "${all_args[@]}")
                args=${args% }  # Remove trailing space
            fi
            ;;
    esac
    
    echo "$args"
}

# Function to find ConfigMaps by labels (simplified approach inspired by old-context.sh)
find_configmaps() {
    log "Finding ConfigMaps with required labels..."
    # Initialize variables
    WINDOWS_CM_NAME=""
    UBUNTU_CM_NAME=""
    EMTD_CM_NAME=""  # EMTD support added: will store emtd configmap name
    # Get all ConfigMaps in the namespace
    local configmaps
    configmaps=$(kubectl_exec get cm -n "$NAMESPACE" -o name 2>/dev/null || echo "")
    if [[ -z "$configmaps" ]]; then
        warn "No ConfigMaps found in namespace $NAMESPACE"
        return 1
    fi
    log "Debug: Found ConfigMaps in namespace $NAMESPACE:"
    echo "$configmaps" | sed 's/configmap\///' | head -10
    # Check each ConfigMap for os labels
    for cm in $configmaps; do
        local cm_name
        cm_name=$(echo "$cm" | sed 's/configmap\///')
        local cm_content
        cm_content=$(kubectl_exec get cm "$cm_name" -n "$NAMESPACE" -o yaml 2>/dev/null || echo "")
        # Check labels for os type (using flexible matching like old-context.sh)
        if echo "$cm_content" | grep -qE 'os:\s*(win11|windows)'; then
            WINDOWS_CM_NAME="$cm_name"
            log "Found Windows ConfigMap: $WINDOWS_CM_NAME"
        elif echo "$cm_content" | grep -qE 'os:\s*(ubuntu22|ubuntu)'; then
            UBUNTU_CM_NAME="$cm_name"
            log "Found Ubuntu ConfigMap: $UBUNTU_CM_NAME"
        elif echo "$cm_content" | grep -qE 'os:\s*(emtd)'; then  # EMTD support added
            EMTD_CM_NAME="$cm_name"
            log "Found EMTD ConfigMap: $EMTD_CM_NAME"
        fi
    done
    if [[ -z "${WINDOWS_CM_NAME:-}" ]]; then
        warn "No Windows ConfigMap found with label 'os: win11' or 'os: windows'"
    fi
    if [[ -z "${UBUNTU_CM_NAME:-}" ]]; then
        warn "No Ubuntu ConfigMap found with label 'os: ubuntu22' or 'os: ubuntu'"
    fi
    if [[ -z "${EMTD_CM_NAME:-}" ]]; then
        warn "No EMTD ConfigMap found with label 'os: emtd'"  # EMTD support added
    fi
}

# Function to update ConfigMap content without duplicates (improved YAML handling)
update_configmap() {
    local cm_name="$1"
    local vm_type="$2"
    
    log "Updating ConfigMap: $cm_name for $vm_type"
    
    # Get current ConfigMap
    local current_cm
    current_cm=$(kubectl_exec get configmap "$cm_name" -n "$NAMESPACE" -o yaml 2>/dev/null)
    if [[ -z "$current_cm" ]]; then
        error "ConfigMap $cm_name not found"
    fi
    
    # Extract current script content
    local current_script
    current_script=$(echo "$current_cm" | awk '/my_script\.sh: \|/{flag=1; next} /^[a-zA-Z]/{flag=0} flag{print}' | sed 's/^[[:space:]]*//')
    
    # Build new USB arguments
    local usb_args
    usb_args=$(build_usb_args_for_vm "$vm_type")
    
    if [[ -z "$usb_args" ]]; then
        warn "No USB devices to assign for $vm_type"
        return
    fi
    
    # Create updated script content
    local updated_script=""
    if [[ -n "$current_script" ]]; then
        # Remove existing USB host arguments and add new ones
        updated_script=$(echo "$current_script" | sed -E "s|<qemu:arg value='-device'/> <qemu:arg value='usb-host[^']*'/>||g")
        # Also remove any existing -usb arguments to avoid duplicates
        updated_script=$(echo "$updated_script" | sed -E "s|<qemu:arg value='-usb'/>||g")
        # Add new USB arguments - different for each VM type with enhanced Windows handling
        case "$vm_type" in
            "windows")
                # For Windows: handle different QEMU command structures (same as YAML file handling)
                if echo "$updated_script" | grep -q "<qemu:arg value='-usb'/>"; then
                    # Standard case: insert USB args before existing -usb argument
                    # shellcheck disable=SC2001
                    updated_script=$(echo "$updated_script" | sed "s|<qemu:arg value='-usb'/>|$usb_args <qemu:arg value='-usb'/>|")
                elif echo "$updated_script" | grep -q "</qemu:commandline>"; then
                    # Case: has closing tag, insert before it with -usb flag
                    # shellcheck disable=SC2001
                    updated_script=$(echo "$updated_script" | sed "s|</qemu:commandline>|$usb_args <qemu:arg value='-usb'/> </qemu:commandline>|")
                elif echo "$updated_script" | grep -q "sed.*</qemu:commandline>"; then
                    # Case: QEMU args are embedded in a sed command (like current Windows files)
                    # shellcheck disable=SC2001
                    updated_script=$(echo "$updated_script" | sed "s|</qemu:commandline>|$usb_args <qemu:arg value='-usb'/> </qemu:commandline>|")
                elif echo "$updated_script" | grep -q "<qemu:commandline>"; then
                    # Fallback: add after opening qemu:commandline with -usb flag
                    # shellcheck disable=SC2001
                    updated_script=$(echo "$updated_script" | sed "s|<qemu:commandline>|<qemu:commandline> $usb_args <qemu:arg value='-usb'/>|")
                else
                    warn "No <qemu:commandline> section found in ConfigMap script for $vm_type"
                fi
                ;;
            "ubuntu"|"emtd")
                # For Ubuntu/EMTD: add only USB args (no -usb flag)
                # shellcheck disable=SC2001
                updated_script=$(echo "$updated_script" | sed "s|</qemu:commandline>|$usb_args </qemu:commandline>|")
                ;;
        esac
    else
        # Create new script template (using heredoc to avoid escaping issues)
        case "$vm_type" in
            "windows")
                read -r -d '' updated_script << 'EOF' || true
#!/bin/sh
tempFile=`mktemp`
echo $4 > $tempFile
sed -i "s|/devices>|/devices> <qemu:commandline> <qemu:arg value='-display'/> <qemu:arg value='gtk,gl=on,full-screen=on,zoom-to-fit=on,window-close=off,connectors.0=DP-2'/> USB_ARGS_PLACEHOLDER <qemu:env name='DISPLAY' value=':0'/> <qemu:arg value='-usb'/> </qemu:commandline>|g" $tempFile
echo $tempFile > /tmp/t.xml
cat $tempFile
EOF
                # Replace placeholder with actual USB args
                updated_script="${updated_script//USB_ARGS_PLACEHOLDER/$usb_args}"
                ;;
            "ubuntu"|"emtd")
                read -r -d '' updated_script << 'EOF' || true
#!/bin/sh
tempFile=`mktemp`
echo $4 > $tempFile
sed -i "s|/devices>|/devices> <qemu:commandline> USB_ARGS_PLACEHOLDER </qemu:commandline>|g" $tempFile
echo $tempFile > /tmp/t.xml
cat $tempFile
EOF
                # Replace placeholder with actual USB args
                updated_script="${updated_script//USB_ARGS_PLACEHOLDER/$usb_args}"
                ;;
        esac
    fi
    
    # Create temporary file for updated ConfigMap using a safer approach
    local temp_file
    temp_file=$(mktemp)
    
    # Extract apiVersion and kind
    local api_version
    api_version=$(echo "$current_cm" | grep "^apiVersion:" | head -1)
    local kind
    kind=$(echo "$current_cm" | grep "^kind:" | head -1)
    
    # Extract metadata section (from metadata: line until next non-indented line)
    local metadata_section
    metadata_section=$(echo "$current_cm" | awk '/^metadata:/{flag=1} flag && /^[a-zA-Z]/ && !/^metadata:/{exit} flag{print}')
    
    # Write complete YAML with proper escaping
    cat > "$temp_file" << EOF
$api_version
$kind
$metadata_section
data:
  my_script.sh: |
EOF
    
    # Add script content with proper indentation, escaping each line
    echo "$updated_script" | while IFS= read -r line; do
        echo "    $line" >> "$temp_file"
    done
    
    # Apply updated ConfigMap
    kubectl_exec apply -f "$temp_file" -n "$NAMESPACE"
    local apply_result=$?
    rm -f "$temp_file"
    
    if [[ $apply_result -eq 0 ]]; then
        log "ConfigMap $cm_name updated successfully"
    else
        error "Failed to update ConfigMap $cm_name"
    fi
}

# Function to update YAML files
update_yaml_files() {
    log "Updating YAML files in: $FILE_LOCATION"
    
    if [[ ! -d "$FILE_LOCATION" ]]; then
        error "Directory $FILE_LOCATION does not exist"
    fi
    
    # Find YAML files with ConfigMap definitions
    local yaml_files
    yaml_files=$(find "$FILE_LOCATION" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
    
    for yaml_file in $yaml_files; do
        info "Checking YAML file: $yaml_file"
        
        # Check if file contains ConfigMap with required labels
        local has_windows_os
        has_windows_os=$(grep -E "os.*win11|win11.*os|os.*windows|windows.*os" "$yaml_file" 2>/dev/null || true)
        local has_ubuntu_os
        has_ubuntu_os=$(grep -E "os.*ubuntu22|ubuntu22.*os|os.*ubuntu|ubuntu.*os" "$yaml_file" 2>/dev/null || true)
        local has_emtd_os
        has_emtd_os=$(grep -E "os.*emtd|emtd.*os" "$yaml_file" 2>/dev/null || true)
        local has_sidecar_type
        has_sidecar_type=$(grep -E "type.*sidecar-script|sidecar-script.*type" "$yaml_file" 2>/dev/null || true)
        local has_configmap
        has_configmap=$(grep -E "kind.*ConfigMap|ConfigMap.*kind" "$yaml_file" 2>/dev/null || true)
        
        # Log what we found
        if [[ -n "$has_configmap" ]]; then
            info "  ✓ Found ConfigMap definition"
        else
            info "  ✗ No ConfigMap definition found"
        fi
        
        if [[ -n "$has_windows_os" ]]; then
            info "  ✓ Found Windows OS label"
        elif [[ -n "$has_ubuntu_os" ]]; then
            info "  ✓ Found Ubuntu OS label"
        elif [[ -n "$has_emtd_os" ]]; then
            info "  ✓ Found EMTD OS label"
        else
            info "  ✗ No OS label found (win11/windows/ubuntu22/ubuntu/emtd)"
        fi
        
        if [[ -n "$has_sidecar_type" ]]; then
            info "  ✓ Found sidecar-script type"
        else
            info "  ✗ No sidecar-script type found"
        fi
        
        # Apply original logic with detailed logging
        if [[ -n "$has_windows_os" && -n "$has_sidecar_type" ]]; then
            log "Updating Windows ConfigMap in: $yaml_file"
            update_yaml_file "$yaml_file" "windows"
        elif [[ -n "$has_ubuntu_os" && -n "$has_sidecar_type" ]]; then
            log "Updating Ubuntu ConfigMap in: $yaml_file"
            update_yaml_file "$yaml_file" "ubuntu"
        elif [[ -n "$has_emtd_os" && -n "$has_sidecar_type" ]]; then
            log "Updating EMTD ConfigMap in: $yaml_file"
            update_yaml_file "$yaml_file" "emtd"
        else
            # Log why the file was skipped
            if [[ -n "$has_windows_os" || -n "$has_ubuntu_os" || -n "$has_emtd_os" ]]; then
                if [[ -z "$has_sidecar_type" ]]; then
                    warn "Skipping $yaml_file: Found OS label but missing 'type: sidecar-script' label"
                fi
            elif [[ -n "$has_sidecar_type" ]]; then
                warn "Skipping $yaml_file: Found sidecar-script type but missing OS label"
            else
                info "Skipping $yaml_file: Not a sidecar-script ConfigMap (missing both OS and type labels)"
            fi
        fi
    done
}

# Function to update individual YAML file
update_yaml_file() {
    local yaml_file="$1"
    local vm_type="$2"
    
    # Create backup
    cp "$yaml_file" "${yaml_file}.backup.$(date +%s)"
    
    # Build USB arguments
    local usb_args
    usb_args=$(build_usb_args_for_vm "$vm_type")
    
    if [[ -z "$usb_args" ]]; then
        warn "No USB devices to assign for $vm_type in $yaml_file"
        return
    fi
    
    log "Adding USB arguments for $vm_type: $usb_args"
    
    # First, remove any existing USB host arguments to avoid duplicates
    sed -i -E "s/<qemu:arg value='-device'\/> <qemu:arg value='usb-host[^']*'\/>[ ]*//g" "$yaml_file"
    
    case "$vm_type" in
        "windows")
            # For Windows, handle different QEMU command structures
            if grep -q "<qemu:arg value='-usb'/>" "$yaml_file"; then
                # Standard case: insert USB args before existing -usb argument
                sed -i "s|<qemu:arg value='-usb'/>|$usb_args <qemu:arg value='-usb'/>|" "$yaml_file"
            elif grep -q "</qemu:commandline>" "$yaml_file"; then
                # Case: has closing tag, insert before it with -usb flag
                sed -i "s|</qemu:commandline>|$usb_args <qemu:arg value='-usb'/> </qemu:commandline>|" "$yaml_file"
            elif grep -q "sed.*</qemu:commandline>" "$yaml_file"; then
                # Case: QEMU args are embedded in a sed command (like current Windows files)
                sed -i "s|</qemu:commandline>|$usb_args <qemu:arg value='-usb'/> </qemu:commandline>|" "$yaml_file"
            elif grep -q "<qemu:commandline>" "$yaml_file"; then
                # Fallback: add after opening qemu:commandline with -usb flag
                sed -i "s|<qemu:commandline>|<qemu:commandline> $usb_args <qemu:arg value='-usb'/>|" "$yaml_file"
            else
                warn "No <qemu:commandline> section found in $yaml_file for $vm_type"
            fi
            ;;
        "ubuntu"|"emtd")
            # For Ubuntu and EMTD, insert USB args only (no -usb flag needed)
            if grep -q "</qemu:commandline>" "$yaml_file"; then
                sed -i "s|</qemu:commandline>|$usb_args </qemu:commandline>|" "$yaml_file"
            elif grep -q "<qemu:arg value='-usb'/>" "$yaml_file"; then
                sed -i "s|<qemu:arg value='-usb'/>|$usb_args|" "$yaml_file"
            else
                # If neither closing tag nor -usb argument exists, add USB args after opening qemu:commandline
                if grep -q "<qemu:commandline>" "$yaml_file"; then
                    sed -i "s|<qemu:commandline>|<qemu:commandline> $usb_args|" "$yaml_file"
                else
                    warn "No <qemu:commandline> section found in $yaml_file for $vm_type"
                fi
            fi
            ;;
    esac
    
    log "Updated $vm_type configuration in: $yaml_file"
}

# Function to restart VMs by deleting VMI and triggering recreation
restart_vms() {
    log "Restarting VMs to apply ConfigMap changes..."
    
    local vmis_deleted=false
    
    # Find VMIs that use the updated ConfigMaps
    if [[ -n "${WINDOWS_CM_NAME:-}" ]]; then
        log "Looking for VMIs using Windows ConfigMap: $WINDOWS_CM_NAME"
       
        # Get all VMIs and check their hookSidecars annotations
        local all_vmis
        all_vmis=$(kubectl_exec get vmi -n "$NAMESPACE" -o name 2>/dev/null)
        info "Debug: Found VMIs: $all_vmis"
        
        for vmi in $all_vmis; do
            local vmi_name
            vmi_name=${vmi#virtualmachineinstance.kubevirt.io/}
            
            info "Debug: Processing VMI $vmi_name for Windows ConfigMap"
            
            # Get the hookSidecars annotation directly using jsonpath
            local vmi_hooks
            vmi_hooks=$(kubectl_exec get vmi "$vmi_name" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.hooks\.kubevirt\.io/hookSidecars}' 2>/dev/null || echo "")
            
            info "Debug: VMI $vmi_name hookSidecars annotation: '$vmi_hooks'"
            
            # Check if the annotation contains our ConfigMap name
            if [[ -n "$vmi_hooks" ]] && [[ "$vmi_hooks" == *"$WINDOWS_CM_NAME"* ]]; then
                log "Found VMI using Windows ConfigMap: $vmi_name"
                log "Deleting VMI to trigger restart: $vmi_name"
                if kubectl_exec delete vmi "$vmi_name" -n "$NAMESPACE"; then
                    vmis_deleted=true
                    # Wait a moment for deletion to process
                    sleep 2
                    # The VirtualMachine controller should automatically recreate the VMI
                    log "VMI $vmi_name deleted. VirtualMachine controller will recreate it with new ConfigMap."
                else
                    warn "Failed to delete VMI $vmi_name"
                fi
                # Continue to check for more VMIs using this ConfigMap
            else
                info "Debug: VMI $vmi_name does not use Windows ConfigMap $WINDOWS_CM_NAME"
            fi
        done
    fi
    
    if [[ -n "${UBUNTU_CM_NAME:-}" || -n "${EMTD_CM_NAME:-}" ]]; then
        log "Looking for VMIs using Ubuntu/EMTD ConfigMap: $UBUNTU_CM_NAME $EMTD_CM_NAME"
        local all_vmis
        all_vmis=$(kubectl_exec get vmi -n "$NAMESPACE" -o name 2>/dev/null)
        for vmi in $all_vmis; do
            local vmi_name
            vmi_name=${vmi#virtualmachineinstance.kubevirt.io/}
            info "Debug: Processing VMI $vmi_name for Ubuntu/EMTD ConfigMap"
            # Get the hookSidecars annotation directly using jsonpath
            local vmi_hooks
            vmi_hooks=$(kubectl_exec get vmi "$vmi_name" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.hooks\.kubevirt\.io/hookSidecars}' 2>/dev/null || echo "")
            info "Debug: VMI $vmi_name hookSidecars annotation: '$vmi_hooks'"
            # Check if the annotation contains our ConfigMap name
            if [[ -n "$vmi_hooks" ]] && { [[ "$vmi_hooks" == *"$UBUNTU_CM_NAME"* ]] || [[ "$vmi_hooks" == *"$EMTD_CM_NAME"* ]]; }; then
                log "Found VMI using Ubuntu/EMTD ConfigMap: $vmi_name"
                log "Deleting VMI to trigger restart: $vmi_name"
                if kubectl_exec delete vmi "$vmi_name" -n "$NAMESPACE"; then
                    vmis_deleted=true
                    # Wait a moment for deletion to process
                    sleep 2
                    log "VMI $vmi_name deleted. VirtualMachine controller will recreate it with new ConfigMap."
                else
                    warn "Failed to delete VMI $vmi_name"
                fi
                # Continue to check for more VMIs using this ConfigMap
            else
                info "Debug: VMI $vmi_name does not use Ubuntu/EMTD ConfigMap $UBUNTU_CM_NAME or $EMTD_CM_NAME"
            fi
        done
    fi
    
    # Monitor recreation if any VMIs were deleted
    if [[ "$vmis_deleted" == true ]]; then
        log "Monitoring VMI recreation after deletion..."
        
        # Give some time for VMs to restart and new VMIs to be created
        sleep 5
        
        # Show current status
        log "Current VM status:"
        kubectl_exec get vm -n "$NAMESPACE" 2>/dev/null || warn "Failed to get VM status"
        
        log "Current VMI status:"
        kubectl_exec get vmi -n "$NAMESPACE" 2>/dev/null || warn "Failed to get VMI status"
    else
        warn "No VMIs were found or deleted that use the updated ConfigMaps"
    fi
}

# Main execution function
main() {
    log "USB Device Detection and Assignment Script"
    log "=========================================="
    # Parse arguments
    parse_arguments "$@"
    # Detect USB devices (supports both Ubuntu and EMTD)
    detect_usb_devices
    # Update ConfigMaps if requested
    if [[ "$UPDATE_CONFIGMAP" == true ]]; then
        find_configmaps
        if [[ -n "${WINDOWS_CM_NAME:-}" ]]; then
            update_configmap "$WINDOWS_CM_NAME" "windows"
        fi
        if [[ -n "${UBUNTU_CM_NAME:-}" ]]; then
            update_configmap "$UBUNTU_CM_NAME" "ubuntu"
        fi
        if [[ -n "${EMTD_CM_NAME:-}" ]]; then  # EMTD support added
            update_configmap "$EMTD_CM_NAME" "emtd"
        fi
        # Restart VMs
        restart_vms
    fi
    # Update YAML files if requested
    if [[ "$UPDATE_FILES" == true ]]; then
        update_yaml_files
    fi
    log "USB device assignment completed successfully!"
}

# Global variables for ConfigMap names
WINDOWS_CM_NAME=""
UBUNTU_CM_NAME=""
EMTD_CM_NAME=""  # EMTD support added

# Execute main function
main "$@"
