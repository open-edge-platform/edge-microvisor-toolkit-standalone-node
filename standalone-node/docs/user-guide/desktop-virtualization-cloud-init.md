
# cloud-init Configuration for Desktop Virtualization Features

Author(s): Krishna, Shankar

Last updated: 25/06/2025

## Overview

This document provides a `cloud-init` configuration for the microvisor image
with desktop virtualization features.

**Use and customize the following configuration script:**

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
    enable: [idv-init]
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
      SUBSYSTEM=="usb", MODE="0664", GROUP="qemu"

# === Custom run commands ===
# List commands or scripts to run at boot.
# Note : Make sure syntax is correct for the commands,if any issues in commands error messages will be present
#        under /var/log/cloud-init-output.log file on EMT image.
# Example:
#   runcmd:
#     - systemctl restart myservice
#     - bash /etc/cloud/test.sh
runcmd:
  - echo $(( 6 * 1024 * 4 )) | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
  - systemctl --user enable idv-init.service
  - udevadm control --reload-rules

```
