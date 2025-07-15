# Standalone Node A/B Update of Edge Microvisor Toolkit

## Get Started

The Edge Microvisor Toolkit operates on an immutable EMT image, where EMT image packages are integrated into the image itself.
To update these packages, a new EMT image with updated package versions is required. This guide provides step-by-step
instructions for setting up the environment necessary to update the Edge Microvisor Toolkit on a standalone node using USB.

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
