<!--
SPDX-FileCopyrightText: (C) 2025 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Installation Guide

1. Execute `build-hook-os-iso.sh` which:

    1. Generates the Hook OS kernel and initramfs file
    2. Creates the `hook-os-iso` with generated kernel and initramfs file
    3. Creates Standalone Installation tar file i.e `sen-installation-files.tar.gz`
       with all required files needed to prepare bootable USB device

2. From repository's root directory run:

    ```shell
    make build
    ```

    Which creates `sen-installation-files.tar.gz` file in `/standalone-node/installation_scripts/out` directory

    Use `sen-installation-files.tar.gz` in next step to prepare the bootable USB

3. Execute `bootable-usb-prepare.sh` which:

    1. Generates the bootable USB device for booting the Hook OS on RAM and installs
       target OS on the Edge Node.

    2. Required inputs for the script:

        - `usb` - valid USB device with name ex. /dev/sda
        - `sen-installation-files.tar.gz` - archive generated in previous step
        - `proxy_ssh_config` - configures proxy settings for the Edge Node (e.g.: if behind the firewall)
        - `ssh_key`- for passwordless connection the Edge node add your `id_rsa.pub` key

        Example:

        ```bash
        sudo ./bootable-usb-prepare.sh /dev/sda sen-installation-files.tar.gz proxy_ssh_config
        ```

    3. Once script creates the bootable USB device it is ready for installation.
