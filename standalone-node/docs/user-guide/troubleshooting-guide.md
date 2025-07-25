# Troubleshooting Guide

Common issues and solutions for Edge Microvisor Toolkit (EMT) Standalone Node.

## Using This Guide

This guide is organized by the phase where issues typically occur:

- [Pre-Installation Issues](#pre-installation-issues) - Problems before creating the bootable USB
- [USB Creation Issues](#usb-creation-issues) - Problems creating the bootable installer
- [Installation Issues](#installation-issues) - Problems during OS installation
- [Post-Installation Issues](#post-installation-issues) - Problems after successful installation
- [Kubernetes Issues](#kubernetes-issues) - Problems with k3s cluster
- [Application Issues](#application-issues) - Problems deploying applications
- [Performance Issues](#performance-issues) - System performance problems

## Pre-Installation Issues

### Build Process Fails

**Problem:** `make build` command fails

**Symptoms:**
```bash
make: *** [build] Error 1
```

**Solutions:**

1. **Check dependencies:**
   ```bash
   # Ensure you have required tools
   which wget git tar gzip
   
   # Install missing dependencies (Ubuntu/Debian)
   sudo apt update
   sudo apt install wget git tar gzip build-essential
   ```

2. **Check disk space:**
   ```bash
   df -h .
   # Ensure you have at least 10GB free space
   ```

3. **Check internet connectivity:**
   ```bash
   wget --spider https://github.com
   ```

### USB Device Not Detected

**Problem:** Cannot find USB device with `lsblk`

**Symptoms:**
- USB drive not showing in `lsblk` output
- Device appears as read-only

**Solutions:**

1. **Try different USB ports:**
   - Use USB 2.0 ports instead of USB 3.0
   - Avoid USB hubs, connect directly

2. **Check USB drive health:**
   ```bash
   # Check if drive is mounted elsewhere
   df -h | grep /dev/sd
   
   # Unmount if necessary
   sudo umount /dev/sdX*
   ```

3. **Verify USB drive compatibility:**
   - Use USB drives 8GB or larger
   - Avoid very old or damaged drives
   - Try a different USB drive

## USB Creation Issues

### Permission Denied Errors

**Problem:** Cannot write to USB device

**Symptoms:**
```bash
dd: failed to open '/dev/sdX': Permission denied
```

**Solutions:**

1. **Run with sudo:**
   ```bash
   sudo ./bootable-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
   ```

2. **Check device ownership:**
   ```bash
   ls -l /dev/sdX
   # Should be owned by root
   ```

### USB Creation Script Fails

**Problem:** `bootable-usb-prepare.sh` script fails

**Common errors and solutions:**

1. **"Device is busy" error:**
   ```bash
   # Unmount all partitions
   sudo umount /dev/sdX*
   
   # Kill any processes using the device
   sudo fuser -km /dev/sdX
   ```

2. **"No space left on device":**
   ```bash
   # Use larger USB drive (16GB+ recommended)
   # Check available space
   df -h /dev/sdX
   ```

3. **Invalid config file:**
   ```bash
   # Verify config-file syntax
   grep -E "user_name|ssh_authorized_keys" config-file
   ```

## Installation Issues

### Boot Process Fails

**Problem:** Edge node won't boot from USB

**Solutions:**

1. **BIOS/UEFI Settings:**
   - Enable UEFI boot mode
   - Disable Secure Boot
   - Set USB as first boot device
   - Enable legacy USB support

2. **Hardware compatibility:**
   - Verify Intel Architecture compatibility
   - Check minimum RAM requirements (8GB)
   - Ensure adequate storage (128GB)

### Installation Hangs or Fails

**Problem:** Installation process stops or fails

**Symptoms:**
- Installation progress stops
- Error messages during installation
- System reboots continuously

**Diagnostic steps:**

1. **Check installation logs:**
   ```bash
   # During installation, switch to different TTY
   Ctrl+Alt+F2
   
   # Check logs
   tail -f /var/log/os-installer.log
   ```

2. **Memory issues:**
   - Verify minimum 8GB RAM
   - Check for faulty RAM modules
   - Try with single RAM stick

3. **Storage issues:**
   - Use SSD instead of HDD if possible
   - Check disk health with SMART tools
   - Ensure SATA/NVMe compatibility

### Network Configuration Fails

**Problem:** Network setup fails during installation

**Solutions:**

1. **Use wired connection:**
   - Wireless setup is not supported during installation
   - Use Ethernet cable for installation

2. **Check proxy settings:**
   ```yaml
   # In config-file, verify proxy configuration
   proxy_url: "http://proxy.company.com:8080"
   no_proxy: "localhost,127.0.0.1,10.0.0.0/8,company.com"
   ```

3. **DHCP issues:**
   - Ensure DHCP server is available
   - Try static IP configuration in config-file

## Post-Installation Issues

### Cannot SSH to Node

**Problem:** SSH connection refused or times out

**Diagnosis:**
```bash
# Test network connectivity
ping <node-ip>

# Test SSH port
telnet <node-ip> 22
```

**Solutions:**

1. **SSH service not running:**
   ```bash
   # On the node console
   sudo systemctl status sshd
   sudo systemctl start sshd
   sudo systemctl enable sshd
   ```

2. **Firewall blocking SSH:**
   ```bash
   # Check firewall status
   sudo systemctl status ufw
   
   # Allow SSH if needed
   sudo ufw allow ssh
   ```

3. **Wrong SSH key:**
   ```bash
   # On development machine, try password authentication
   ssh -o PasswordAuthentication=yes user@<node-ip>
   
   # Add your SSH key manually
   ssh-copy-id user@<node-ip>
   ```

### User Account Issues

**Problem:** Cannot log in with configured credentials

**Solutions:**

1. **Check user creation:**
   ```bash
   # On node console, verify user exists
   getent passwd | grep <username>
   ```

2. **Reset password:**
   ```bash
   # As root on node console
   passwd <username>
   ```

3. **Check SSH key configuration:**
   ```bash
   # Verify SSH key is in authorized_keys
   cat /home/<username>/.ssh/authorized_keys
   ```

## Kubernetes Issues

### k3s Service Not Running

**Problem:** Kubernetes cluster not starting

**Diagnosis:**
```bash
# Check k3s status
sudo systemctl status k3s

# Check logs
sudo journalctl -u k3s -f
```

**Solutions:**

1. **Resource constraints:**
   ```bash
   # Check available resources
   free -h
   df -h
   
   # Ensure minimum 8GB RAM and sufficient disk space
   ```

2. **Network issues:**
   ```bash
   # Check network configuration
   ip addr show
   ip route show
   
   # Verify DNS resolution
   nslookup kubernetes.default.svc.cluster.local
   ```

3. **Restart k3s:**
   ```bash
   sudo systemctl restart k3s
   sudo systemctl enable k3s
   ```

### Pods Not Starting

**Problem:** Kubernetes pods stuck in Pending or CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -A

# Describe problematic pods
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>
```

**Solutions:**

1. **Resource constraints:**
   ```bash
   # Check node resources
   kubectl top nodes
   kubectl describe node
   ```

2. **Image pull issues:**
   ```bash
   # Check if images can be pulled
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

3. **Storage issues:**
   ```bash
   # Check storage classes
   kubectl get storageclass
   kubectl get pv,pvc -A
   ```

## Application Issues

### Helm Charts Fail to Deploy

**Problem:** Helm installation fails

**Diagnosis:**
```bash
# Check helm status
helm list -A

# Get detailed status
helm status <release-name> -n <namespace>
```

**Solutions:**

1. **Repository issues:**
   ```bash
   # Update helm repositories
   helm repo update
   
   # Verify repository access
   helm search repo <chart-name>
   ```

2. **Resource conflicts:**
   ```bash
   # Check for existing resources
   kubectl get all -n <namespace>
   
   # Clean up if necessary
   helm uninstall <release-name> -n <namespace>
   ```

### Container Images Won't Pull

**Problem:** Cannot pull container images

**Solutions:**

1. **Network connectivity:**
   ```bash
   # Test internet access from node
   curl -I https://registry.k8s.io
   ```

2. **Proxy configuration:**
   ```bash
   # Check containerd proxy settings
   sudo systemctl edit containerd
   
   # Add proxy configuration
   [Service]
   Environment="HTTP_PROXY=http://proxy:8080"
   Environment="HTTPS_PROXY=http://proxy:8080"
   Environment="NO_PROXY=localhost,127.0.0.1"
   ```

## Performance Issues

### High CPU Usage

**Problem:** System running slow, high CPU usage

**Diagnosis:**
```bash
# Check CPU usage
top
htop

# Check system load
uptime
```

**Solutions:**

1. **Identify resource-hungry processes:**
   ```bash
   # Find top CPU consumers
   ps aux --sort=-%cpu | head -10
   ```

2. **Optimize k3s:**
   ```bash
   # Reduce k3s resource usage
   sudo systemctl edit k3s
   
   # Add resource limits
   [Service]
   ExecStart=
   ExecStart=/usr/local/bin/k3s server --kubelet-arg="max-pods=50"
   ```

### High Memory Usage

**Problem:** Out of memory errors, swap usage

**Solutions:**

1. **Increase swap space:**
   ```bash
   # Create swap file
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   
   # Make permanent
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

2. **Optimize container limits:**
   ```bash
   # Set resource limits for deployments
   kubectl patch deployment <name> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"512Mi"}}}]}}}}'
   ```

## Getting Additional Help

### Log Collection

Use the provided log collection script:

```bash
# On the edge node
sudo ./edgenode-logs-collection.sh

# This creates a tar.gz file with all relevant logs
```

### Essential Log Locations

- **Installation logs:** `/var/log/os-installer.log`
- **Cloud-init logs:** `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`
- **Kubernetes logs:** `journalctl -u k3s`
- **System logs:** `journalctl -f`
- **Container logs:** `kubectl logs <pod-name> -n <namespace>`

### Debug Mode

Enable debug mode for more verbose logging:

```bash
# For k3s
sudo systemctl edit k3s
# Add: ExecStart=/usr/local/bin/k3s server --debug

# For containerd
sudo systemctl edit containerd
# Add: ExecStart=/usr/bin/containerd --log-level debug
```

### Support Channels

- **GitHub Issues:** [Report bugs](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/issues)
- **Documentation:** Check other guides in this directory
- **Community:** Search existing issues for similar problems

### Before Reporting Issues

Include this information:

1. **Hardware specifications**
2. **Steps to reproduce the problem**
3. **Error messages (full text)**
4. **Log files** (use log collection script)
5. **Configuration files** (remove sensitive data)

---

**Last updated:** July 25, 2025
