# Desktop Virtualization Guide

Enable GPU-accelerated virtual machines on your Edge Microvisor Toolkit (EMT) Standalone Node.

## Overview

This guide shows how to deploy EMT with desktop virtualization capabilities, enabling you to run
Windows and Linux virtual machines with GPU acceleration, display virtualization, and USB passthrough.

**Time required:** 1-2 hours  
**Difficulty:** Advanced  
**Target audience:** VDI deployments, advanced users

## What You'll Build

By the end of this guide, you'll have:

- EMT node with desktop virtualization features enabled
- GPU SR-IOV configuration for VM hardware acceleration
- Display virtualization for direct monitor connection
- USB passthrough for keyboard, mouse, and other devices
- Network bridge configuration for VM connectivity

## Desktop Virtualization Features

The EMT Desktop Virtualization image provides enterprise-grade virtualization capabilities:

### Core Features

- **SR-IOV GPU Support:** Single Root I/O Virtualization for Intel integrated graphics
- **Display Virtualization:** Direct display output from VMs using Intel integrated graphics
- **USB Passthrough:** Full USB device passthrough including HID devices
- **Network Bridge:** Advanced networking for VM connectivity
- **Self-contained:** Includes container runtime, k3s, and virtualization add-ons

### Validated Platforms

- **Windows 11 VMs** with GPU acceleration
- **Linux VMs** with GPU acceleration and AI compute offload
- **Mixed workloads** combining VMs and containers

## Architecture Overview

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                    Customer Applications                     │
├─────────────────┬─────────────────┬─────────────────────────┤
│ Windows 11 VM   │ Linux AI VM     │ Containerized AI App    │
│ (GPU Display)   │ (GPU Compute)   │                         │
└─────────────────┴─────────────────┴─────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                 Resource Management                          │
├─────────────────┬─────────────────┬─────────────────────────┤
│ GPU SR-IOV      │ Hugepages       │ Network Bridge          │
│ Virtual Functions│ Memory          │ Multiple Interfaces     │
└─────────────────┴─────────────────┴─────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│           k3s + Virtualization Extensions                   │
│  • KubeVirt  • SR-IOV Device Plugin  • Multus CNI          │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│        EMT Desktop Virtualization Image                     │
│          (Hypervisor + Container Runtime)                   │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│      Intel Core Platform with Integrated GPU               │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Hardware Requirements

- **Intel Core processor** with integrated graphics (i915 driver support)
- **16GB RAM minimum** (32GB+ recommended for multiple VMs)
- **256GB storage** (SSD strongly recommended)
- **Multiple monitors** (if using display virtualization)
- **USB devices** for passthrough testing

### Supported Processors

Verified on:

- 13th Gen Intel® Core™ i7-1365URE (12 cores, 62GB RAM tested)
- Other 12th/13th Gen Intel Core processors with integrated graphics

### Software Prerequisites

Same as the [Quick Start Guide](quick-start-guide.md), plus:

- **VM management tools** (virt-manager, or kubectl for KubeVirt)
- **VNC client** (for headless VM access)

## Resource Usage

The desktop virtualization infrastructure has moderate overhead:

### System Resource Consumption

| Component | CPU Usage | Memory Usage | Storage |
|-----------|-----------|---------------|---------|
| **Base k3s + Extensions** | ~5% (0.6 cores) | ~3GB | ~2GB |
| **Per Windows VM** | 2-4 cores | 4-8GB | 60GB+ |
| **Per Linux VM** | 1-2 cores | 2-4GB | 20GB+ |

> **Note:** Memory usage scales with hugepage allocation. Tune according to your VM requirements.

## Reference cloud-init for EMT image with Desktop Virtualization and networking features

- NOTE: The linux username `guest` is used throughout this configuration (e.g., in sudoers, systemd user services, etc.).
  To use a different user, replace all occurrences of `guest` with the `user_name` that is set in the
  `User Credentials` section of the `config-file`.
  For example, if your user is 'myuser', replace `guest` with `myuser` in:
  - `/etc/sudoers.d/idv_scripts`
  - `/etc/systemd/system/getty@tty1.service.d/autologin.conf`
  - `runcmd` section (sudo -u ...)
  - Any other relevant locations in this file.

```yaml
#cloud-config

# === Enable or disable systemd services ===
# List services to enable or disable.
# Note : Make sure Services should be part of the Base Image to enable or disable.
# Example:
#   services:
#     enable: [docker, ssh]
#     disable: [apache2]
services:
    enable: []
    disable: []

# === Create custom configuration files ===
# To create a file, specify its path,permission and content.
# Note : you can create as many files(shell,text,yaml) as you wish,just expand the write_files: with prefix -path for next file
# Note : Make sure scripts/files passing to cloud-init file well tested,if any issues in the script/file error messages 
#        will be present under /var/log/cloud-init-output.log file on EMT image.
# Example:
#   write_files:
#     - path: /etc/cloud/test.sh
#        permissions: '0644'
#       content: |
#         #!/bin/sh
#         echo "This is Example"
write_files:
  - path: /etc/environment
    append: true
    content: |
      export INTEL_IDV_GPU_PRODUCT_ID=$(cat /sys/devices/pci0000:00/0000:00:02.0/device | sed 's/^0x//')
      export INTEL_IDV_GPU_VENDOR_ID=$(cat /sys/devices/pci0000:00/0000:00:02.0/vendor | sed 's/^0x//')
  - path: /etc/systemd/system/nw_custom_file.service
    content: |
      [Unit]
      Description=network custom file services
      After=network.target
      [Service]
      WorkingDirectory=/opt/user-apps/scripts/management/
      ExecStart=bash /opt/user-apps/scripts/management/nw_custom_service.sh
      Restart=on-failure
      [Install]
      WantedBy=multi-user.target
  # autologin.conf configures automatic login for the specified user on tty1.
  # Change AUTOLOGIN_USER to your intended username if not using 'guest' user.
  # autologin.conf configures automatic login for the specified user on tty1.
  # Change AUTOLOGIN_USER to your intended username if not using 'guest' user.
  - path: /etc/systemd/system/getty@tty1.service.d/autologin.conf
    permissions: '0644'
    content: |
      [Service]
      Environment="AUTOLOGIN_USER=guest"
      ExecStart=
      ExecStart=-/sbin/agetty -o '-f -- \\u' --autologin $AUTOLOGIN_USER --noclear %I $TERM

  # Change `guest` to your intended username if not using 'guest' user.
  - path: /etc/sudoers.d/idv_scripts
    permissions: '0644'
    content: |
      guest ALL=(ALL) NOPASSWD: /usr/bin/X, \
      /usr/bin/idv/init/setup_sriov_vfs.sh, \
      /usr/bin/idv/init/setup_display.sh, \
      /usr/bin/idv/launcher/start_vm.sh, \
      /usr/bin/idv/launcher/start_all_vms.sh, \
      /usr/bin/idv/launcher/stop_vm.sh, \
      /usr/bin/idv/launcher/stop_all_vms.sh

  - path: /usr/share/X11/xorg.conf.d/10-serverflags.conf
    permissions: '0644'
    content: |
      Section "ServerFlags"
           Option "StandbyTime" "0"
           Option "SuspendTime" "0"
           Option "OffTime"     "0"
           Option "BlankTime"   "0"
      EndSection

  - path: /usr/share/X11/xorg.conf.d/10-extensions.conf
    permissions: '0644'
    content: |
      Section "Extensions"
          Option "DPMS" "false"
      EndSection

  - path: /etc/udev/rules.d/99-usb-qemu.rules
    permissions: '0644'
    content: |
      ACTION=="add", SUBSYSTEM=="usb", MODE="0664", GROUP="qemu", OWNER="qemu"

    # Change `guest` to your intended username if not using 'guest' user.
  - path: /etc/cloud/rc.xml
    permissions: '0644'
    owner: 'guest:guest'
    content: |
      <openbox_config xmlns="http://openbox.org/3.6/rc">
        <keyboard>
          <keybind key="A-C-t">
            <action name="Execute">
              <command>xterm</command>
            </action>
          </keybind>
        </keyboard>
      </openbox_config>

  - path: /etc/cloud/custom_network.conf
    permissions: '0644'
    content: |
      # custom_network.conf
      # Update this file to specify custom network settings for the bridge configuration script.
      # Set the CIDR, gateway, netmask, IP range, and DNS server for your environment.
      # If EdgeNode cannot reach Internet. DNS update needed.

      BR_NAME="br0"                    # Bridge interface name
      BR_CIDR="199.168.1.0/24"         # Bridge interface IP address and subnet (CIDR notation)
      BR_GATEWAY="199.168.1.1"         # Default gateway for the bridge network
      BR_NETMASK="24"                  # Netmask for the bridge network (as a number, e.g., 24)
      BR_START_RANGE="199.168.1.2"     # Start of the DHCP/static IP range for clients
      BR_END_RANGE="199.168.1.20"      # End of the DHCP/static IP range for clients
      BR_DNS_NAMESERVER="8.8.8.8"      # DNS server to use for the bridge network.

# === Custom run commands ===
# List commands or scripts to run at boot.
# Note : Make sure syntax is correct for the commands,if any issues in commands error messages will be present 
#        under /var/log/cloud-init-output.log file on EMT image. 
# Example:
#   runcmd:
#     - systemctl restart myservice
#     - bash /etc/cloud/test.sh
# If custom scripts in user-apps are getting not getting invoked. please make sure to add the scripts in "user-apps" folder
# Example:
#   runcmd:
#     - bash /opt/user-apps/network-config.sh /etc/cloud/custom_network.conf
runcmd:
  # Source /etc/environment to ensure newly created environment variables are available to subsequent commands in this boot sequence
  - source /etc/environment
  - udevadm control --reload-rules
  # Add the user to render group (assuming username is 'user')
  - sudo usermod -a -G render user
  - sudo -u user mkdir -p /home/user/.config/openbox/
  - sudo -u user mv /etc/cloud/rc.xml /home/user/.config/openbox/rc.xml
  # Change `guest` to your intended username if not using 'guest' user.
  - sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user enable idv-init.service
  - sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user start idv-init.service
  - sudo systemctl start nw_custom_file.service
  - test -f /opt/user-apps/scripts/management/apply_bridge_nad.sh && bash /opt/user-apps/scripts/management/apply_bridge_nad.sh /etc/cloud/custom_network.conf > /etc/cloud/apply_bridge_nad.log 2>&1
  # User shall add their application specific commands to automate the application deployment like this
  # bash /opt/user-apps/scripts/management/app-deploy.sh
```
