# Standalone Node A/B Update of Edge Microvisor Toolkit

## Get Started

The Edge Microvisor Toolkit runs on a fixed EMT image, with packages embedded directly into the image.
To update these packages, you must create a new EMT image that includes the updated packages.
This guide offers detailed instructions for preparing the environment needed to update the Edge Microvisor
Toolkit on a standalone node using a USB drive.

### Step 1: Prerequisites

Ensure that your standalone node is equipped with the designated version of the immutable image. Adhere to all
the steps provided in the [Get Started Guide](get-started-guide.md#prerequisites) to complete the initial setup.

#### **Important Notes**

Note #1: Please be aware that updates to the Edge Microvisor Toolkit are not compatible with mutable or ISO images.

Note #2: Updates are supported only with Edge Microvisor Toolkit(EMT) images, which means updates must be performed
using the most recent EMT image versions. Users should regularly check for new EMT image releases to plan their
updates, as reverting to older images is not supported.

Note #3: The Edge Microvisor Toolkit allows updates only within the same EMT image family: DV, RT, or NON_RT.
This means DV → DV, RT → RT, and NON_RT → NON_RT updates are supported, while cross-family updates are blocked.

Note #4: Image type validation is content-first. During update, the script inspects the mounted update image
partition to detect type. Filename/path is only used as a fallback if content-based detection is unavailable.

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

- For `-c`, provide only a checksum file (`.sha256sum`).

  > **Important:** Passing an image file (`.raw`, `.raw.gz`, `.img`, `.img.gz`) to `-c` is rejected.

#### Step 2.2 URL Mode

- Initiate the microvisor update by running the script with these options:

  ```bash
  sudo ./os-update.sh -u <base url> -r <release> -v <build version>
  ```

  Example:

  ```bash
  sudo ./os-update.sh -u https://files-rs.edgeorchestration.intel.com/files-edge-orch/repository/microvisor/non_rt -r 3.0 -v 20250718.0822
  ```

### Step 2.3 EMT Image Type Detection and Validation Flow

Before applying the update, the script validates compatibility between the currently running EMT image and
the new update image.

Detection flow for the update image:

1. Decompress update image and mount the update partition in read-only mode.
2. Detect image type from image content (priority order):
   - `/etc/image-id` in update image (`partition metadata`)
   - DV markers (`/usr/bin/idv` or DV launcher in image)
   - kernel release metadata (`/lib/modules/...`)
   - kernel config (`/boot/config-*`)
3. If still not detected, fallback to path/filename parsing.

The script prints these lines during validation:

```text
Current EMT type: <DV|RT|NON_RT|UNKNOWN>
Image type: <DV|RT|NON_RT|UNKNOWN>
Image type source: <source>
```

`Image type source` values:

- `partition metadata`, `partition dv marker`, `partition dv launcher`, `kernel release`, `kernel config`:
  content-derived detection (preferred).
- `path`, `filename`:
  fallback detection when content-based signals are unavailable.

Mismatch behavior:

```text
Error: <current_type> EMT detected, but <image_type> image provided.
Please provide a <current_type> upgrade version instead.
```

Example:

- Current EMT type: DV
- Image type: RT
- Image type source: kernel config
- Result: update blocked due to family mismatch.

Rename test behavior:

- If a DV image file is renamed to look like RT/NON_RT, content-based detection still classifies it as DV when
  metadata/markers are present in the image.
- Filename/path naming affects result only when content-based detection cannot determine the type.

### Automatic Reboot

- Once the update has completed, the EMT provisioned node will automatically reboot into the updated EMT image.
  
- After a successful boot, confirm that the system is operating properly with the new image:
  
  ```bash
  sudo bootctl list
  ```

### Multi-upgrade Behavior and Commit Script Handling

- `commit_update.sh` is recreated on each update run so the latest logic is always used.
- Installer hook insertion is idempotent:
  if the `commit_update.sh` entry already exists in `installer.cfg`, it is reused and not duplicated.
- In repeated upgrades, if credential backup files are not available at commit time, the script logs warnings and
  skips credential restore for that boot instead of hard-failing the full commit flow.
- Commit stage logs are written to:

  ```text
  /var/log/os-update-commit.log
  ```

### Review the specifics of the updated image

  ```bash
  cat /etc/image-id
  ```
