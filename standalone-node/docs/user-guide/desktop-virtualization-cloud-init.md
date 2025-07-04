# Reference cloud-init for EMT image with Desktop Virtualization features

- NOTE: The username `guest` is used throughout this configuration (e.g., in sudoers, systemd user services, etc.).
  To use a different user, replace all occurrences of `guest` with the `user_name` that is set in the `User Credentials` section of the `config-file`.
  For example, if your user is 'myuser', replace `guest` with `myuser` in:
  - /etc/sudoers.d/idv_scripts
  - /etc/systemd/system/getty@tty1.service.d/autologin.conf
  - runcmd section (sudo -u ...)
  - Any other relevant locations in this file.

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

    # Change `guest` to your intended username if not using 'guest' user.
  - path: /home/guest/.config/openbox/rc.xml
    permissions: '0644'
    owner: 'guest:guest'
    defer: true
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
  # Change `guest` to your intended username if not using 'guest' user.
  - sudo -u guest XDG_RUNTIME_DIR=/run/user/$(id -u guest) systemctl --user enable idv-init.service
  - sudo -u guest XDG_RUNTIME_DIR=/run/user/$(id -u guest) systemctl --user start idv-init.service
  - test -f /opt/user-apps/network_config.sh && bash /opt/user-apps/network_config.sh /etc/cloud/custom_network.conf || echo "network_config.sh is missing"
  - test -f /opt/user-apps/apply_bridge_nad.sh && bash /opt/user-apps/apply_bridge_nad.sh /etc/cloud/custom_network.conf > /etc/cloud/apply_bridge_nad.log 2>&1 &  
```
