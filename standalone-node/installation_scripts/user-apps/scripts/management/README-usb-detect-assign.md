<!--
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
-->

# USB Device Detection and Assignment Script

![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)
![Kubernetes](https://img.shields.io/badge/kubernetes-compatible-326ce5.svg)

## Overview

This script provides robust USB device detection and assignment for virtual machines running in Kubernetes
environments with KubeVirt. It automatically detects and assigns USB devices based on specific requirements
to ensure optimal performance and functionality for both Ubuntu and Windows VMs.

### Device Assignment Strategy

- **Ubuntu VMs**: First USB 3.0 device (for high-speed storage and devices)
- **Windows VMs**: Keyboard, mouse, and touchscreen devices (for complete input control)

### Operating Modes

1. **ConfigMap Update Mode** (`-c`) - Updates Kubernetes ConfigMaps and restarts VMs
2. **File Update Mode** (`-f`) - Updates ConfigMap YAML files stored on disk
3. **Both Modes** (`-a`) - Performs both operations simultaneously

## Features

### Core Features

- **USB 3.0 Detection**: Automatic identification of high-speed devices (5Gbps+)
- **HID Device Recognition**: Smart keyboard and mouse detection
- **Hub Support**: Proper handling of USB hub-connected devices
- **Duplicate Prevention**: Ensures no device is assigned multiple times
- **Comprehensive Logging**: Detailed operation tracking and debugging
- **Auto-restart**: Automatic VM restart to apply new configurations
- **Flexible kubectl**: Auto-detects `kubectl` vs `k3s kubectl` commands

## Requirements

### System Requirements

- **OS**: Linux system with USB devices
- **Privileges**: Root access (required for USB device information)
- **Dependencies**: `lsusb` and `lsusb -t` commands (usbutils package)
- **Kubernetes**: `kubectl` or `k3s kubectl` for ConfigMap operations
- **KubeVirt**: VM management platform for Kubernetes

### VM Configuration Requirements

ConfigMaps must have specific labels for identification:

- **Windows ConfigMaps**: `os: win11` or `os: windows`
- **Ubuntu ConfigMaps**: `os: ubuntu22` or `os: ubuntu`

### Supported Devices

- **USB 3.0 Devices**: Any device with 5Gbps+ transfer speed
- **HID Devices**: Keyboards, mice, and generic HID devices
- **Touchscreen Devices**:

  - ILI Technology (`222a:0001`)
  - Devices with "multi-touch", "touchscreen", or "touch screen" in description
  - Easily extensible for additional vendors

## Installation & Setup

### Prerequisites

```bash
# Install required packages (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install usbutils curl

# Install kubectl (if not already installed)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
lsusb --version
kubectl version --client
```

### Download & Setup

```bash
# Clone the repository
git clone <repository-url>
cd usb-detect-n-assign

# Make script executable
chmod +x usb-detect-assign.sh
chmod +x test-usb-detection.sh
chmod +x validate.sh

# Run test suite to verify functionality
./test-usb-detection.sh all
```

## Usage

### Quick Start

```bash
# Update ConfigMaps and restart VMs
sudo ./usb-detect-assign.sh -c

# Update YAML files in default location
sudo ./usb-detect-assign.sh -f

# Update both ConfigMaps and files
sudo ./usb-detect-assign.sh -a
```

### Advanced Usage

```bash
# Custom file location
sudo ./usb-detect-assign.sh -f /custom/path/charts/

# Custom namespace
sudo ./usb-detect-assign.sh -n production-vms -c

# Complete workflow with custom settings
sudo ./usb-detect-assign.sh -a /opt/custom/charts/ -n production-vms

# Show help
./usb-detect-assign.sh -h
```

### Command Options

| Option | Description | Example |
| -------- | ----------- | ------- |
| `-c, --configmap` | Update ConfigMaps and restart VMs | `-c` |
| `-f, --files [LOCATION]` | Update YAML files | `-f /custom/path/` |
| `-a, --all [LOCATION]` | Do both operations | `-a` |
| `-n, --namespace NAME` | Specify Kubernetes namespace | `-n user-apps` |
| `-h, --help` | Show help message | `-h` |

## Detection Algorithm

### USB Device Discovery

The script uses multiple detection methods for comprehensive device discovery:

```bash
lsusb                           # Lists all USB devices
lsusb -t                        # Shows USB topology tree
/proc/bus/input/devices         # Input device information
```

### Device Categorization

#### USB 3.0 Detection

- **Speed Detection**: Devices with speeds ≥ 5000M (5 Gbps)
- **Tree Analysis**: Checks `lsusb -t` output for speed information
- **Priority**: First found USB 3.0 device assigned to Ubuntu

#### HID Device Detection

- **Device Classes**: Human Interface Device class identification
- **Priority Order**: Raritan KVM → Generic HID → Other devices
- **Assignment**: First two devices assigned as keyboard and mouse

#### Touchscreen Detection (New in v3.0.0)

- **Vendor ID**: Specific support for ILI Technology (`222a:0001`)
- **Description Patterns**:
  - `multi-touch`
  - `touchscreen`
  - `touch screen`
  - `ili technology`
- **Expandable**: Easy addition of new touchscreen vendors

### Port Path Resolution

For hub-connected devices, the script resolves proper port paths:

```bash
# Direct connection: hostbus=3,hostport=4
# Hub connection: hostbus=3,hostport=8.3
```

## Configuration Examples

### Generated QEMU Arguments

#### Ubuntu VM (USB 3.0 Storage)

```xml
<qemu:arg value='-device'/>
<qemu:arg value='usb-host,hostbus=2,hostport=2'/>
<qemu:arg value='-usb'/>
```

#### Windows VM (Keyboard + Mouse + Touchscreen)

```xml
<qemu:arg value='-device'/>
<qemu:arg value='usb-host,hostbus=1,hostport=5'/>
<qemu:arg value='-device'/>
<qemu:arg value='usb-host,hostbus=1,hostport=6'/>
<qemu:arg value='-device'/>
<qemu:arg value='usb-host,hostbus=1,hostport=4'/>
<qemu:arg value='-usb'/>
```

### Example ConfigMap Structure

#### Windows ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sidecar-win11-dp1
  namespace: user-apps
  labels:
    os: win11
    type: sidecar-script
data:
  my_script.sh: |
    #!/bin/sh
    tempFile=`mktemp`
    echo $4 > $tempFile
    sed -i "s|/devices>|/devices> <qemu:commandline> <qemu:arg value='-display'/> \
         <qemu:arg value='gtk,gl=on,full-screen=on'/> \
         <qemu:arg value='-device'/> <qemu:arg value='usb-host,hostbus=1,hostport=5'/> \
         <qemu:arg value='-device'/> <qemu:arg value='usb-host,hostbus=1,hostport=6'/> \
         <qemu:arg value='-device'/> <qemu:arg value='usb-host,hostbus=1,hostport=4'/> \
         <qemu:env name='DISPLAY' value=':0'/> \
         <qemu:arg value='-usb'/> </qemu:commandline>|g" $tempFile
    echo $tempFile > /tmp/t.xml
    cat $tempFile
```

#### Ubuntu ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sidecar-ub22-dp1
  namespace: user-apps
  labels:
    os: ubuntu22
    type: sidecar-script
data:
  my_script.sh: |
    #!/bin/sh
    tempFile=`mktemp`
    echo $4 > $tempFile
    sed -i "s|/devices>|/devices> <qemu:commandline> <qemu:arg value='-device'/> \
            <qemu:arg value='usb-host,hostbus=2,hostport=2'/> \
            <qemu:arg value='-usb'/> </qemu:commandline>|g" $tempFile
    echo $tempFile > /tmp/t.xml
    cat $tempFile
```

## Testing & Validation

### Run Test Suite

```bash
# Test all scenarios
./test-usb-detection.sh all

# Test with current system devices
./test-usb-detection.sh current

# Test specific scenario
./test-usb-detection.sh production
./test-usb-detection.sh test
./test-usb-detection.sh dev

# Verbose testing with detailed output
./test-usb-detection.sh -v all

# Run validation script
./validate.sh
```

### Test Scenarios

The test suite includes pre-recorded USB device data from different environments:

| Scenario | Description | Test Data |
| ---------- | ----------- | --------- |
| `production` | Production system with multiple devices | `production_lsusb.txt` |
| `test` | Test environment setup | `test_lsusb.txt` |
| `dev` | Development environment | `dev_lsusb.txt` |
| `current` | Live system testing | Real-time `lsusb` output |

### Example Detection Output

```bash
[2025-01-11 15:00:42] USB Device Detection and Assignment Script
[2025-01-11 15:00:42] ==========================================
[INFO] USB Detection Strategy:
[INFO] 1. Find first USB 3.0 device for Ubuntu
[INFO] 2. Find keyboard, mouse, and touchscreen devices for Windows
[INFO] 3. Handle hub-connected devices appropriately

[INFO] Found HID device: Dell Computer Corp. KB216 Wired Keyboard (Bus 001, Device 005)
[INFO] Found HID device: Pixart Imaging, Inc. Optical Mouse (Bus 001, Device 006)
[INFO] Found touchscreen device: ILI Technology Corp. Multi-Touch Screen (Bus 001, Device 004)
[INFO] Found USB 3.0 device: SanDisk Corp. SanDisk 3.2Gen1 (Bus 002, Device 002, Speed 5000M)

✓ Assigned USB 3.0 device to Ubuntu: SanDisk Corp. SanDisk 3.2Gen1 (Bus 2, Device 2, Port 2)
✓ Assigned keyboard device to Windows: Dell Computer Corp. KB216 Wired Keyboard (Bus 1, Device 5, Port 4)
✓ Assigned mouse device to Windows: Pixart Imaging, Inc. Optical Mouse (Bus 1, Device 6, Port 3)
✓ Assigned touchscreen device to Windows: ILI Technology Corp. Multi-Touch Screen (Bus 1, Device 4, Port 5)

[2025-01-11 15:00:43] Final USB Device Assignment Summary:
[2025-01-11 15:00:43]   Ubuntu (USB 3.0): Bus 2, Port 2
[2025-01-11 15:00:43]   Windows Keyboard: Bus 1, Port 4
[2025-01-11 15:00:43]   Windows Mouse: Bus 1, Port 3
[2025-01-11 15:00:43]   Windows Touchscreen: Bus 1, Port 5
```

## Troubleshooting

### Common Issues & Solutions

#### 1. No USB 3.0 Devices Found

**Problem**: Script reports no USB 3.0 devices available for Ubuntu.

**Diagnosis**:

```bash
# Check for USB 3.0 controllers
lsusb | grep -i "3.0\|xhci"

# Check device speeds
lsusb -t | grep -E "[5-9][0-9]{3}M|[1-9][0-9]{4}M"

# Check for SuperSpeed devices
lsusb -v | grep -i "superspeed"
```

**Solutions**:

- Ensure USB 3.0 devices are properly connected
- Check if devices are being recognized by the system
- Verify USB 3.0 controller is working (`lspci | grep -i usb`)

#### 2. ConfigMap Not Found

**Problem**: Script cannot find ConfigMaps with required labels.

**Diagnosis**:

```bash
# Check ConfigMap labels in your namespace
kubectl get configmap -n user-apps --show-labels

# Look for ConfigMaps with required labels
kubectl get configmap -n user-apps -l "os=win11"
kubectl get configmap -n user-apps -l "os=ubuntu22"

# Check if kubectl context is correct
kubectl config current-context
kubectl config get-contexts
```

**Solutions**:

- Ensure kubectl context points to correct cluster
- Verify namespace exists and you have permissions
- Check that ConfigMaps have the required OS labels (`os=win11`, `os=ubuntu22`, etc.)
- Verify the script auto-detects kubectl command correctly

#### 3. Script Updates Files But Not ConfigMaps

**Problem**: Script runs in `-a` (both) mode but only updates files.

**Diagnosis**:

```bash
# Check kubectl permissions
kubectl auth can-i get configmaps -n user-apps
kubectl auth can-i update configmaps -n user-apps

# Test kubectl connectivity
kubectl get configmaps -n user-apps
```

**Solutions**:

- Ensure proper RBAC permissions for ConfigMap operations
- Verify network connectivity to Kubernetes cluster
- Check if ConfigMap labels match exactly what the script expects

#### 4. Permission Issues

**Problem**: Script fails with permission errors.

**Solutions**:

```bash
# Ensure root privileges for USB device access
sudo ./usb-detect-assign.sh -c

# Check USB device permissions
ls -la /dev/bus/usb/

# Verify script is executable
chmod +x usb-detect-assign.sh
```

#### 5. Hub Device Detection Issues

**Problem**: USB hub-connected devices not properly detected.

**Diagnosis**:

```bash
# Check USB topology
lsusb -t

# Look for proper port paths in the tree structure
lsusb -v | grep -A5 -B5 "hub"
```

**Solutions**:

- Ensure hub is properly powered and connected
- Check for hub compatibility issues
- Verify port path resolution in script logs

#### 6. Touchscreen Not Detected

**Problem**: Touchscreen devices not being assigned to Windows VM.

**Diagnosis**:

```bash
# Check for touchscreen devices
lsusb | grep -i "touch\|multi"

# Look for ILI Technology devices
lsusb | grep "222a:0001"

# Check device descriptions
lsusb -v | grep -i "touch\|multi"
```

**Solutions**:

- Verify touchscreen is properly connected and powered
- Check if device appears in `lsusb` output
- Add custom detection patterns for your touchscreen vendor

### Debug Mode

Enable verbose output for debugging:

```bash
# Run with bash debug mode
bash -x ./usb-detect-assign.sh -c

# Enable verbose logging in test suite
./test-usb-detection.sh -v all
```

### Getting Help

If you encounter issues not covered above:

1. **Run the test suite**: `./test-usb-detection.sh all`
2. **Check the logs**: Look for detailed error messages in script output
3. **Verify requirements**: Ensure all prerequisites are met
4. **Test incrementally**: Start with `-f` mode before trying `-c` mode
5. **Check examples**: Review the `examples/` directory for proper ConfigMap structure

## Error Handling

The script includes comprehensive error handling:

- **USB Detection Failures** - Falls back to generic device assignment
- **ConfigMap Access Issues** - Provides clear error messages
- **File Permission Problems** - Creates alternative temporary files
- **Invalid YAML** - Validates before applying changes

## Performance Considerations

- **Minimal System Impact** - Quick USB device scanning
- **Efficient Updates** - Only updates changed configurations
- **Backup Creation** - Automatic backup of modified files
- **Rollback Support** - Helm rollback integration for VM restart

## Future Enhancements

### Planned Features

1. **Configuration File Support** - YAML/JSON configuration for device assignment rules
2. **Custom Device Filters** - More sophisticated device selection criteria
3. **Multiple VM Support** - Support for more than 2 VMs per assignment
4. **Real-time Monitoring** - Daemon mode for USB hotplug events
5. **Web Interface** - GUI for device assignment management
6. **Metrics & Monitoring** - Prometheus metrics for device assignment status
7. **Enhanced Security** - Better validation and sanitization of inputs

### Extensibility Points

- **Device Detection**: Easy to add new device types and vendors
- **VM Types**: Simple to extend beyond Ubuntu/Windows
- **Assignment Rules**: Configurable priority and fallback logic
- **Output Formats**: Support for different ConfigMap templates

### Contributing

We welcome contributions! Areas where help is needed:

- Additional touchscreen vendor support
- Support for other input device types (joysticks, gamepads)
- Enhanced error handling and recovery
- Performance optimizations
- Documentation improvements

---

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.

## Authors

- **Main Developer**: USB device detection and assignment implementation
- **Contributors**: Testing, documentation, and feature enhancements

## Acknowledgments

- **old-context.sh**: Reference implementation that inspired the kubectl detection logic
- **KubeVirt Community**: For the excellent virtualization platform
- **Kubernetes**: For the robust container orchestration platform

---

Last updated: January 2026
