# Pre-conditions for Build Environment

Ensure that Docker is installed and all necessary settings (such as proxy configurations) are properly configured.  
**Note:** Ubuntu 22.04 is the preferred OS for the build setup.

---

## Create the Standalone Installation Tar File

To create the standalone installation tar file with all required files for preparing a bootable USB device, run the following command:

```bash
make build
```

This will build the hook OS and generate the `sen-installation-files.tar.gz` file.  
The file will be located under the `$(pwd)/installation-scripts/out` directory.

---

## Copy Files to Prepare the Bootable USB

Extract the contents of `sen-installation-files.tar.gz`:

```bash
tar -xzf sen-installation-files.tar.gz
```

The extracted files will include:

- `usb-bootable-files.tar.gz`
- `config-file` 
- `bootable-usb-prepare.sh`
---

## Prepare the Bootable USB Device

Use the `bootable-usb-prepare.sh` script to:

1. Generate a bootable USB device for booting the hook OS into RAM.
2. Install the OS on the edge node.

### Required Inputs for the Script:

- **`usb`**: A valid USB device name (e.g., `/dev/sda`).
- **`usb-bootable-files.tar.gz`**: The tar file containing bootable files.
- **`config-file`**: Configuration file for proxy settings (if the edge node is behind a firewall).  
    - Includes `ssh_key`, which is your Linux device's `id_rsa.pub` key for passwordless SSH access to the edge node.
    - User credentials: set the user name and password for edge node.

**Note:** Providing proxy settings is optional if the edge node does not require them to access internet services.

### Example Command:

```bash
sudo ./bootable-usb-prepare.sh /dev/sda usb-bootable-files.tar.gz config-file
```

Once the script completes, the bootable USB device will be ready for installation.

---

## Login to the Edge Node After Successful Installation

Use the credentials provided as input while preparing the bootable usb drive

## For Kubernetes pods status run bellow command

source /etc/environment && export KUBECONFIG

kubectl get pods 
