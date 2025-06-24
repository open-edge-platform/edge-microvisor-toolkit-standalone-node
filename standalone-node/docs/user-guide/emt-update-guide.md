# Standalone Node A/B Update of Edge Microvisor Toolkit

## Get Started

The Edge Microvisor Toolkit operates on an immutable EMT image, where packages are integrated into the image itself.
To update these packages, you need to build a new EMT image with updated packages. This guide provides step-by-step
instructions for setting up the environment necessary to update the Edge Microvisor Toolkit on a standalone node using USB drive.

### Step 1: Prerequisites

Make sure your standalone node is provisioned with the specified version of immutable image.
Follow all instructions outlined in the [Get Started Guide](get-started-guide.md#prerequisites) to complete the initial setup.

> **Note**: Keep in mind that the standalone node updates do not support mutable or ISO images
  of Edge Microvisor Toolkit.

#### 1.1: Prepare the USB Drive

- Connect the USB drive to your developer system and identify the correct USB disk using the following command:

  ```bash
  lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,FSTYPE,MOUNTPOINT,MODEL
  ```

  > **Note:** Ensure you select the correct USB drive to avoid data loss.

- Copy `standalone-installation-files.tar.gz` to the developer system to prepare the bootable USB drive.

- Extract the contents of `standalone-installation-files.tar.gz`.

  ```bash
  tar -xzf standalone-installation-files.tar.gz
  ```

- The extracted files will include:

  ```bash
  usb-bootable-files.tar.gz
  write-image-to-usb.sh
  config-file
  bootable-usb-prepare.sh
  download_images.sh
  edgenode-logs-collection.sh
  ```

- Download the Edge Microvisor Toolkit image and the corresponding sha256sum file.

  > **Note:** Only download the microvisor image from "no Auth" file server public registry, export BASE_URL_NO_AUTH_RS

  ```bash
  wget <artifact-base-url>/<version>/edge-readonly-<version>-signed.raw.gz
  wget <artifact-base-url>/<version>/edge-readonly-<version>-signed.raw.gz.sha256sum
  ```

  Example:

  ```bash
  wget https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250611.0526/edge-readonly-3.0.20250611.0526-signed.raw.gz
  wget https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt/3.0/20250611.0526/edge-readonly-3.0.20250611.0526-signed.raw.gz.sha256sum
  ```

  Alternatively, for "no Auth" file server public registry

  ```bash
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<release>.<build date>-signed.raw.gz"
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<version>.<build date>signed.sha256sum"
  ```

  Example:

  ```bash
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250608.2200-signed.raw.gz
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250608.2200-signed.raw.gz.sha256sum
  ```

- To update a new Edge Microvisor Toolkit image, first execute the preparation script to write it to the USB drive:

  ```bash
  sudo ./write-image-to-usb.sh </dev/sdX> </path/to/microvisor_image.raw.gz> </path/to/microvisor_image.raw.gz.sha256sum>
  ```

  Example:

  ```bash
  sudo ./write-image-to-usb.sh /dev/sdc /path/to/microvisor_image.raw.gz /path/to/microvisor_image.raw.gz.sha256sum
  ```

## Step 2: Perform Edge Microvisor Toolkit Update on Standalone Node

> **Note:** You can choose either direct mode or URL mode for the microvisor update.

### Direct Mode

- Unplug the prepared bootable USB drive from the developer system.
- Plug the bootable USB drive into the standalone edge node.
- Mount the USB device to `/mnt`:

  ```bash
  sudo mount /dev/sdX1 /mnt
  ```

- Run the script located in `/etc/cloud` to start the microvisor update:

  ```bash
  sudo ./os-update.sh -i /path/to/microvisor_image.raw.gz -c /path/to/microvisor_image.sha256sum
  # Example:
  sudo ./os-update.sh -i /mnt/edge-readonly-3.0.20250611.0526-signed.raw.gz -c /mnt/edge-readonly-3.0.20250608.2200-signed.raw.gz.sha256sum
  ```

### URL Mode

- To start the microvisor update, execute the script with the following options:

  ```bash
  sudo ./os-update.sh -u <base url> -r <release> -v <build version>
  ```

  Example:

  ```bash
  sudo ./os-update.sh -u https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt -r 3.0 -v 20250608.2200
  ```

- Automatic Reboot

  Once the update has completed, the standalone edge node will automatically reboot into the
  updated microvisor OS.

- Upon successful boot, verify that the system is running correctly with the new image:

  ```bash
  sudo bootctl list
  ```

- Check the details of the updated image:

  ```bash
  cat /etc/image-id
  ```
