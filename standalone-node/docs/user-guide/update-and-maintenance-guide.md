# Update and Maintenance Guide

Keep your Edge Microvisor Toolkit (EMT) Standalone Node current and healthy.

## Overview

This guide covers updating your EMT node to newer versions and performing routine maintenance.
EMT uses an A/B update system that provides safe, atomic updates with automatic rollback capability.

**Time required:** 30-60 minutes  
**Difficulty:** Intermediate  
**Target audience:** Operations teams, system administrators

## Update System Overview

EMT uses an immutable operating system with A/B partitioning:

- **Immutable OS:** The base system cannot be modified, only replaced
- **A/B Updates:** Two system partitions allow safe updates with instant rollback
- **Atomic Updates:** Either the entire update succeeds or fails - no partial states
- **Automatic Rollback:** Failed updates automatically revert to the previous version

### What Gets Updated

- **Operating system kernel and drivers**
- **System packages and security updates**
- **Container runtime and Kubernetes (k3s)**
- **EMT-specific components**

### What Doesn't Change

- **User data and applications** (preserved across updates)
- **Kubernetes workloads** (continue running during updates)
- **Configuration files** (maintained automatically)

## Prerequisites

Before updating your EMT node:

### Verify Current System

```bash
# Check current image version
cat /etc/image-id

# Check system health
systemctl status k3s
kubectl get nodes
kubectl get pods -A
```

### Backup Considerations

While user data is preserved, consider backing up:

- **Application data:** Export important application data
- **Custom configurations:** Save any manual configuration changes
- **Kubeconfig files:** Back up kubectl configuration

```bash
# Example backup commands
kubectl get all -A -o yaml > k8s-backup.yaml
cp /etc/rancher/k3s/k3s.yaml ~/kubeconfig-backup.yaml
```

## Update Methods

EMT supports two update methods:

### Method 1: Direct Mode (USB-based)

Best for: Offline environments, controlled updates

### Method 2: URL Mode (Network-based)

Best for: Online environments, automated updates

## Method 1: Direct Mode Update

### Step 1: Prerequisites

Ensure your standalone node is provisioned with the specified version of the Edge Microvisor Toolkit with immutable image.
Please note that EMT-S updates do not support EMT mutable or ISO images.
Follow all instructions outlined in the [Get Started Guide](Get-Started-Guide.md#Prerequisites) to complete the initial setup.

#### 1.1: Prepare the USB Drive

- Connect the USB drive to your developer system and identify the correct USB disk using the following command

  ```bash
  lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,FSTYPE,MOUNTPOINT,MODEL
  ```

  > **Note:** Ensure you select the correct USB drive to avoid data loss.

- Copy the standalone installation tar file to the developer system to prepare the bootable USB.

- Extract the contents of `standalone-installation-files.tar.gz`

  ```bash
  tar -xzf standalone-installation-files.tar.gz
  ```

- The extracted files will include

  ```bash
  usb-bootable-files.tar.gz
  write-image-to-usb.sh
  config-file
  bootable-usb-prepare.sh
  download_images.sh
  edgenode-logs-collection.sh
  ```

- Download the Edge Microvisor Toolkit image and the corresponding sha256sum file

  > **Note:** TO DO: only download the microvisor image from no Auth file registry, export BASE_URL_NO_AUTH_RS
  
  ```bash
  wget <artifact-base-url>/<version>/edge-readonly-<version>-signed.raw.gz
  wget <artifact-base-url>/<version>/edge-readonly-<version>-signed.raw.gz.sha256sum
  ```

  Example usage:

  ```bash
  wget https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250611.0526/edge-readonly-3.0.20250611.0526-signed.raw.gz
  wget https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250611.0526/edge-readonly-3.0.20250611.0526-signed.raw.gz.sha256sum
  ```

  Alternatively, for no Auth File server public registry

  ```bash
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<release>.<build date>-signed.raw.gz"
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<version>.<build date>signed.sha256sum"
  ```

  Example usage:

  ```bash
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250608.2200-signed.raw.gz
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250608.2200-signed.raw.gz.sha256sum
  ```

- Execute the preparation script to write the new Edge Microvisor Toolkit image which needs to be updated to the USB drive

  ```bash
  sudo ./write-image-to-usb.sh /dev/sdX /path/to/microvisor_image.raw.gz /path/to/microvisor_image.raw.gz.sha256sum
  ```

  Example usage:

  ```bash
  sudo ./write-image-to-usb.sh /dev/sdc /path/to/microvisor_image.raw.gz /path/to/microvisor_image.raw.gz.sha256sum
  ```

## Step 2: Perform Edge Microvisor Toolkit Update on Standalone Node

> **Note:** User can refer to two modes: Direct mode or URL mode for microvisor update.

### Direct Mode

- Unplug the prepared bootable USB from the developer system.
- Plug the bootable USB drive into the standalone node.
- Mount the USB device to `/mnt`:

  ```bash
  sudo mount /dev/sdX1 /mnt
  ```

- Run the microvisor update script located in `/etc/cloud`

  ```bash
  sudo ./os-update.sh -i /path/to/microvisor_image.raw.gz -c /path/to/microvisor_image.sha256sum
  # Example:
  sudo ./os-update.sh -i /mnt/edge-readonly-3.0.20250611.0526-signed.raw.gz -c /mnt/edge-readonly-3.0.20250608.2200-signed.raw.gz.sha256sum
  ```

### URL Mode

- Execute the microvisor update script with the following options

  ```bash
  sudo ./os-update.sh -u <base url> -r <release> -v <build version>
  # Example:
  sudo ./os-update.sh -u https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt -r 3.0 -v 20250608.2200
  ```

- Automatic Reboot
  The standalone edge node will automatically reboot into the updated Microvisor OS after the update process completes

- Upon successful boot, verify that the system is running correctly with the new image

  ```bash
  sudo bootctl list
  ```

- Check the updated image details in `/etc/image-id`

  ```bash
  cat /etc/image-id
  ```
