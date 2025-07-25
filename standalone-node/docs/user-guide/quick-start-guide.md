# Quick Start Guide

Get your Edge Microvisor Toolkit (EMT) Standalone Node up and running in under an hour.

## Overview

This guide covers the fastest path to a working EMT node using default settings. For advanced
configuration options, see the [Complete Setup Guide](complete-setup-guide.md).

**Time required:** 30-60 minutes  
**Difficulty:** Beginner  
**Target audience:** First-time users, evaluators

## What You'll Build

By the end of this guide, you'll have:

- A standalone edge node running EMT with Kubernetes (k3s)
- A sample WordPress application to verify everything works
- Remote access from your development machine

## Before You Start

### You'll Need

- **Intel-based computer** for the edge node ([supported processors](../../../README.md#supported-processor-families))
- **Linux development machine** to create the bootable USB
- **8GB USB drive** (will be formatted)
- **Ethernet cable** and internet connection
- **Basic Linux knowledge** (command line, SSH)

### Quick Check

Verify your development machine has these tools:

```bash
# Check required tools
which wget git lsblk mkfs.vfat
```

If any are missing, install them with your package manager.

## Step 1: Download and Prepare

### 1.1 Get the Source Code

```bash
# Clone the repository
git clone https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node
cd edge-microvisor-toolkit-standalone-node

# Build the installer package
sudo make build
```

**Expected result:** A file named `standalone-installation-files.tar.gz` is created in
`./installation-scripts/out/`

### 1.2 Prepare Your USB Drive

⚠️ **Warning:** This will erase all data on your USB drive!

```bash
# Find your USB drive (look for your USB device, usually /dev/sdb or /dev/sdc)
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Replace /dev/sdX with your actual USB device
export USB_DEVICE=/dev/sdX

# Unmount any mounted partitions
sudo umount ${USB_DEVICE}* 2>/dev/null || true

# Wipe and format the USB drive
sudo wipefs --all --force ${USB_DEVICE}
sudo mkfs.vfat ${USB_DEVICE}
```

### 1.3 Extract and Configure

```bash
# Extract the installer
cd installation-scripts/out
tar -xzf standalone-installation-files.tar.gz

# Download required Kubernetes components
sudo ./download_images.sh NON-RT
```

## Step 2: Configure Your Installation

Edit the `config-file` to set your preferences:

```bash
# Make a backup first
cp config-file config-file.backup

# Edit the configuration
nano config-file
```

### Required Changes

Update these sections in `config-file`:

**SSH Access** - Replace with your public key:

```yaml
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc... your-public-key-here
```

**User Account** - Set your preferred username and password:

```yaml
# User Credentials
user_name: "myuser"
user_password: "your-secure-password"
```

**Network** (if needed) - Add proxy settings if required:

```yaml
# Proxy Configuration (only if needed)
proxy_url: "http://proxy.company.com:8080"
no_proxy: "localhost,127.0.0.1,10.0.0.0/8"
```

To get your SSH public key:

```bash
# Generate a new key if you don't have one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Display your public key to copy
cat ~/.ssh/id_rsa.pub
```

## Step 3: Create Bootable USB

```bash
# Create the bootable USB (replace /dev/sdX with your USB device)
sudo ./bootable-usb-prepare.sh ${USB_DEVICE} usb-bootable-files.tar.gz config-file
```

**Expected output:** Success message confirming USB creation.

## Step 4: Install on Edge Node

### 4.1 Boot from USB

1. **Insert USB** into your edge node
2. **Boot from USB** (press F12, F2, or DEL during startup to access boot menu)
3. **Wait for installation** (15-30 minutes)
4. **Automatic reboot** when complete

### 4.2 Verify Installation

After the node reboots, it will show login prompt. Log in with your configured credentials.

```bash
# Check that Kubernetes is running
k get nodes

# Expected output:
# NAME          STATUS   ROLES                  AGE   VERSION
# your-node     Ready    control-plane,master   5m    v1.28.x+k3s1

# Check all pods are running
k get pods -A

# Expected: All pods should be Running or Completed
```

## Step 5: Connect from Your Development Machine

### 5.1 Get the Node's IP Address

On the edge node:

```bash
# Find the IP address
ip addr show | grep "inet " | grep -v 127.0.0.1
```

Note the IP address (e.g., 192.168.1.100).

### 5.2 Set Up Remote Access

On your development machine:

```bash
# Set the edge node IP
export NODE_IP=192.168.1.100  # Replace with actual IP

# Copy the Kubernetes config
mkdir -p ~/.kube
scp myuser@${NODE_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update the config to use the node's IP
sed -i "s/127\.0\.0\.1/${NODE_IP}/g" ~/.kube/config

# Test the connection
kubectl get nodes
```

## Step 6: Deploy a Test Application

Let's deploy WordPress to verify everything works:

```bash
# Add the Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create a simple WordPress configuration
cat > wordpress-values.yaml << EOF
persistence:
  enabled: false
mariadb:
  primary:
    persistence:
      enabled: false
  auth:
    password: "test123"
    rootPassword: "test123"
wordpressUsername: admin
wordpressPassword: test123
service:
  type: ClusterIP
resources:
  requests:
    cpu: 0m
    memory: 0Mi
EOF

# Install WordPress
helm install my-wordpress bitnami/wordpress \
  --namespace wordpress \
  --create-namespace \
  -f wordpress-values.yaml \
  --version 19.4.3

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s
```

### Test Your Application

```bash
# Forward the port to access WordPress
kubectl port-forward --namespace wordpress svc/my-wordpress 8080:80 &

# Open your browser to http://localhost:8080
# Login with: admin / test123
```

## Troubleshooting Quick Fixes

### USB Creation Failed

```bash
# Make sure USB is unmounted
sudo umount /dev/sdX* 2>/dev/null || true

# Try a different USB device or port
lsblk  # Check device name changed
```

### Installation Stuck

- Check BIOS settings: Enable UEFI boot, disable Secure Boot
- Try a different USB port
- Check hardware compatibility with Intel Architecture requirements

### Can't SSH to Node

```bash
# Check if SSH service is running on the node
systemctl status sshd

# Check firewall on your development machine
ping ${NODE_IP}  # Should respond
```

### Kubernetes Not Ready

```bash
# On the edge node, check k3s status
sudo systemctl status k3s

# Check logs if there are issues
sudo journalctl -u k3s -f
```

## What's Next?

🎉 **Congratulations!** You have a working EMT Standalone Node.

### Explore More

- **Deploy AI workloads**: Try TensorFlow, PyTorch, or OpenVINO applications
- **Scale up**: Add worker nodes to your cluster
- **Secure your deployment**: Review security best practices
- **Enable virtualization**: Try the [Desktop Virtualization Guide](desktop-virtualization-guide.md)

### Learn More

- [Complete Setup Guide](complete-setup-guide.md) - Advanced configuration options
- [Pre-loading Applications](pre-loading-user-apps.md) - Automate app deployment
- [Update and Maintenance](update-and-maintenance-guide.md) - Keep your system current

### Need Help?

- Check the [Troubleshooting Guide](troubleshooting-guide.md)
- Review logs: `/var/log/cloud-init-output.log` and `journalctl -u k3s`
- Ask questions: [GitHub Issues](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/issues)

---

**Last updated:** July 25, 2025
