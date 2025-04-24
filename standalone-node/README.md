### Pre-conditions for Build Environment

Ensure that Docker is installed and all necessary settings (such as proxy configurations) are properly configured.  
Refer to the links below for Docker installation and proxy setup:

- [Docker Installation Docs](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Proxy Setup](https://docs.docker.com/engine/daemon/proxy/)

> **Note:** Ubuntu 22.04 is the preferred OS for the build setup.

---

### Create the Standalone Installation Tar File

To create the standalone installation tar file with all required files for preparing a bootable USB device, run the following command:
> **Note:** If the development system is behind a firewall, ensure to add the proxy configuration in the `hook_os/config` file.

```bash
make build
```

This command will build the hook OS and generate the `sen-installation-files.tar.gz` file.  
The file will be located in the `$(pwd)/installation-scripts/out` directory.

---

### Copy Files to Prepare the Bootable USB

Extract the contents of `sen-installation-files.tar.gz`:

```bash
tar -xzf sen-installation-files.tar.gz
```

The extracted files will include:

- `usb-bootable-files.tar.gz`
- `config-file`
- `bootable-usb-prepare.sh`
- `edgenode-logs-collection.sh`

---

### Prepare the Bootable USB Device

Use the `bootable-usb-prepare.sh` script to:

1. Generate a bootable USB device for booting the hook OS into RAM.
2. Install the OS on the edge node.

### Required Inputs for the Script:

- **`usb`**: A valid USB device name (e.g., `/dev/sda`).
- **`usb-bootable-files.tar.gz`**: The tar file containing bootable files.
- **`config-file`**: Configuration file for proxy settings (if the edge node is behind a firewall).  
    - Includes `ssh_key`, which is your Linux device's `id_rsa.pub` key for passwordless SSH access to the edge node.
    - User credentials: Set the username and password for the edge node.

> **Note:** Providing proxy settings is optional if the edge node does not require them to access internet services.

### Example Command:

```bash
sudo ./bootable-usb-prepare.sh /dev/sda usb-bootable-files.tar.gz config-file
```

Once the script completes, the bootable USB device will be ready for installation.

---

### Login to the Edge Node After Successful Installation

Use the credentials provided as input while preparing the bootable USB drive.

---

### Check Kubernetes Pods Status

Run the following commands to check the status of Kubernetes pods:

```bash
source /etc/environment && export KUBECONFIG
kubectl get pods -A
```

---

### Collect Edge Node Logs from Development System

Use the `edgenode-logs-collection.sh` script to collect logs from the edge node. Ensure the system has the SSH key provided for passwordless access.

### Example Command:

```bash
./edgenode-logs-collection.sh <edgenode-username> <edgenode-ip>
```
