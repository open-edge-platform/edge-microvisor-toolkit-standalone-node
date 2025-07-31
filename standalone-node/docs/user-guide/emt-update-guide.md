# Standalone Node A/B Update of Edge Microvisor Toolkit

## Get Started

The Edge Microvisor Toolkit runs on a fixed EMT image, with packages embedded directly into the image.
To update these packages, you must create a new EMT image that includes the updated packages.
This guide offers detailed instructions for preparing the environment needed to update the Edge Microvisor
Toolkit on a standalone node using a USB drive.

### Step 1: Prerequisites

Ensure that your standalone node is equipped with the designated version of the immutable image. Adhere to all the steps provided in the [Get Started Guide](get-started-guide.md#prerequisites) to complete the initial setup.

#### **Important Notes**:
Note #1: Please be aware that updates to the Edge Microvisor Toolkit are not compatible with mutable or ISO images.

Note #2: Updates are supported only with Edge Microvisor Toolkit(EMT) images, which means updates must be performed using the most
recent EMT image versions. Users should regularly check for new EMT image releases to plan their updates, as reverting to older
images is not supported.

Note #3: The Edge Microvisor Toolkit allows updates solely within its specific image types, such as DV or non-RT. This means that
systems initially set up with a particular EMT image type, like non-RT, can only be updated using images of the same type.

#### 1.1: Prepare the USB Drive

- Attach the USB drive to your development system and use the following command to locate the appropriate USB disk:

  ```bash
  lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,FSTYPE,MOUNTPOINT,MODEL
  ```

  > **Note:** Make sure to choose the correct USB drive to prevent any data loss.

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

- Obtain the Edge Microvisor Toolkit image along with its corresponding sha256sum file.

  > **Note:** Download the microvisor image exclusively from the file server's public registry and export BASE_URL_NO_AUTH_RS.

  ```bash
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<release>.<build date>.raw.gz"
  wget "<BASE_URL_NO_AUTH_RS>/edge-readonly-<version>.<build date>.sha256sum"
  ```

  Example:

  ```bash
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250717.0734.raw.gz
  wget https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt/edge-readonly-3.0.20250717.0734.raw.gz.sha256sum
  ```

- To update the Edge Microvisor Toolkit image, begin by running the preparation script to transfer it onto the USB drive:

  ```bash
  sudo ./write-image-to-usb.sh </dev/sdX> </path/to/microvisor_image.raw.gz> </path/to/microvisor_image.raw.gz.sha256sum>
  ```

  Example:

  ```bash
  sudo ./write-image-to-usb.sh /dev/sdc /path/to/microvisor_image.raw.gz /path/to/microvisor_image.raw.gz.sha256sum
  ```

### Step 2: Execute the Edge Microvisor Toolkit Update on a Standalone Node

> **Note:** You can choose either direct mode or URL mode for the microvisor update.

#### Step 2.1 Direct Mode

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
  sudo ./os-update.sh -i /mnt/edge-readonly-3.0.20250718.0822.raw.gz -c /mnt/edge-readonly-3.0.20250718.0822.raw.gz.sha256sum
  ```

#### Step 2.2 URL Mode

- Initiate the microvisor update by running the script with these options:

  ```bash
  sudo ./os-update.sh -u <base url> -r <release> -v <build version>
  ```

  Example:

  ```bash
  sudo ./os-update.sh -u https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt -r 3.0 -v 20250718.0822
  ```

### Automatic Reboot

  Once the update has completed, the EMT provisioned node will automatically reboot into the updated EMT image.
  
- After a successful boot, confirm that the system is operating properly with the new image:
  
  ```bash
  sudo bootctl list
  ```

### Review the specifics of the updated image:

  ```bash
  cat /etc/image-id
  ```
