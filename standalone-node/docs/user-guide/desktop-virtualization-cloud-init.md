# Reference cloud-init for EMT image with Desktop Virtualization features

# NOTE: The username `guest` is used throughout this configuration (e.g., in sudoers, systemd user services, etc.).
# To use a different user, replace all occurrences of `guest` with your intended username.
# For example, if your user is 'myuser', replace `guest` with `myuser` in:
#   - /etc/sudoers.d/idv_scripts
#   - /etc/systemd/system/getty@tty1.service.d/autologin.conf
#   - runcmd section (sudo -u ...)
#   - Any other relevant locations in this file.

Author(s): Krishna, Shankar

Last updated: 25/06/2025

## Abstract

This document provides a reference `cloud-init` configuration for customers using the Edge Microvisor Toolkit image
with Desktop Virtualization features.

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
  
  # hugepages.service pre-allocates enough 2MB hugepages for 2 VMs with 6GB RAM each.
  # Formula: 6 (memory per VM in GB) * 2048 (2MB pages per GB) * 2 (Number of VMs) = total hugepages needed. 
  # Adjust the 'memory per VM in GB' and 'number of VMs' as needed.
  - path: /usr/bin/allocate_hugepages.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      HUGEPAGES=$(( 6 * 2048 * 2 ))
      HUGEPAGES_KB=$((HUGEPAGES * 2048))
      MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
      MEM_FREE_KB=$(awk '/MemFree/ {print $2}' /proc/meminfo)
      if [ "$MEM_TOTAL_KB" -le "$HUGEPAGES_KB" ] || [ "$MEM_FREE_KB" -le "$HUGEPAGES_KB" ]; then
        echo "ERROR: Not enough memory for hugepages allocation: need $HUGEPAGES_KB kB, total $MEM_TOTAL_KB kB, free $MEM_FREE_KB kB" >&2
        exit 1
      fi
      echo $HUGEPAGES > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

  - path: /etc/systemd/system/hugepages.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Configure Hugepages
      Before=k3s.service

      [Service]
      Type=oneshot
      ExecStart=/usr/bin/allocate_hugepages.sh

      [Install]
      WantedBy=multi-user.target

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
  # Source /etc/environment to ensure newly created environment variables are available to subsequent commands in this boot sequence
  - source /etc/environment
  - udevadm control --reload-rules
  - systemctl enable hugepages.service
  - systemctl start hugepages.service
  # Change `guest` to your intended username if not using 'guest' user.
  - sudo -u guest XDG_RUNTIME_DIR=/run/user/$(id -u guest) systemctl --user enable idv-init.service
  - sudo -u guest XDG_RUNTIME_DIR=/run/user/$(id -u guest) systemctl --user start idv-init.service

```
