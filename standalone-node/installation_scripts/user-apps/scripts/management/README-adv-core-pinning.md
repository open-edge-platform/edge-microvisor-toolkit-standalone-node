<!-- SPDX-FileCopyrightText: (C) 2025 Intel Corporation -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# vCPU Core Pinning Script

Advanced QEMU vCPU thread management script for KubeVirt VMs with automatic monitoring and restart detection.

## Features

- **Dual VM Support**: Manage CPU affinity for up to two VMs simultaneously
- **Automatic Restart Detection**: Monitors VM PIDs and reapplies CPU pinning after VM restarts
- **Continuous Monitoring**: Configurable watch intervals for persistent CPU affinity management
- **Daemon Mode**: Background operation with syslog logging
- **Robust Error Handling**: Comprehensive validation and error reporting
- **Kubernetes Integration**: Works with KubeVirt VMs across multiple namespaces
- **CPU Validation**: Validates CPU lists against system capabilities

## Requirements

- **Root privileges**: Script must run with `sudo` (required for `taskset` operations)
- **k3s/kubectl**: For Kubernetes namespace discovery
- **KubeVirt environment**: Compatible with KubeVirt VM naming conventions
- **Linux system**: Uses `ps`, `pgrep`, `taskset`, and other Linux utilities

## Installation

1. Download the script:

   ```bash
   wget https://your-repo/adv-core-pinning.sh
   chmod +x adv-core-pinning.sh
   ```

2. Ensure you have the required dependencies:

    ```bash
   # Check if k3s is available
   which k3s
   
   # Check if taskset is available
   which taskset
   ```

## Usage

### Basic Syntax

```bash
sudo ./adv-core-pinning.sh [COMMAND] --vm1 <vm_name1> --cpu1 <cpu_list1> [OPTIONS]
```

### Commands

- `start`: Start CPU pinning (default command)
- `stop`: Stop running daemon
- `restart`: Restart daemon with new settings
- `status`: Show daemon status and recent activity
- `check`: Show VM status without changing CPU affinity

### Required Arguments

- `--vm1 <name>`: First VM name
- `--cpu1 <list>`: CPU list for VM1 (e.g., `0-3` or `0,2,4,6`)

### Optional Arguments

- `--vm2 <name>`: Second VM name (enables dual VM mode)
- `--cpu2 <list>`: CPU list for VM2 (required if `--vm2` is specified)
- `--namespace <ns>`: Kubernetes namespace (default: search all user namespaces)
- `--watch <seconds>`: Watch interval in seconds (default: 30, 0 = run once)
- `--daemon`: Run in daemon mode (background, no terminal output)
- `--help`, `-h`: Show help message

## Examples

### Single VM Operations

#### Run Once (No Monitoring)

```bash
# Set CPU affinity for one VM and exit
sudo ./adv-core-pinning.sh start --vm1 win11-vm1 --cpu1 0-3 --watch 0
```

#### Continuous Monitoring with single VM

```bash
# Monitor and maintain CPU affinity every 30 seconds
sudo ./adv-core-pinning.sh start --vm1 win11-vm1 --cpu1 0-3 --watch 30
```

#### Specific Namespace

```bash
# Target VM in specific namespace
sudo ./adv-core-pinning.sh start --vm1 test-vm --cpu1 0,2,4 --namespace user-apps
```

### Dual VM Operations

#### Basic Dual VM Setup

```bash
# Pin two VMs to different CPU sets
sudo ./adv-core-pinning.sh start --vm1 ub22-vm --cpu1 0-3 --vm2 win11-vm --cpu2 4-7
```

#### Production Setup with Monitoring

```bash
# Continuous monitoring for two VMs
sudo ./adv-core-pinning.sh start \
  --vm1 ub22-vm --cpu1 0-2 \
  --vm2 win11-vm --cpu2 4-6 \
  --namespace user-apps \
  --watch 60
```

#### Daemon Mode (Background)

```bash
# Run in background with syslog logging
sudo ./adv-core-pinning.sh start \
  --vm1 ub22-vm --cpu1 0-2 \
  --vm2 win11-vm --cpu2 4-6 \
  --namespace user-apps \
  --watch 60 \
  --daemon
```

### Daemon Management

#### Start Daemon

```bash
# Start daemon for your VMs
sudo ./adv-core-pinning.sh start \
  --vm1 ub22-vm --cpu1 0-2 \
  --vm2 win11-vm --cpu2 4-6 \
  --namespace user-apps \
  --watch 60 \
  --daemon
```

#### Check Daemon Status

```bash
# Check if daemon is running and view recent activity
sudo ./adv-core-pinning.sh status --vm1 ub22-vm --vm2 win11-vm
```

#### Stop Daemon

```bash
# Gracefully stop the daemon
sudo ./adv-core-pinning.sh stop --vm1 ub22-vm --vm2 win11-vm
```

#### Restart Daemon

```bash
# Restart daemon with new settings
sudo ./adv-core-pinning.sh restart \
  --vm1 ub22-vm --cpu1 0-2 \
  --vm2 win11-vm --cpu2 4-6 \
  --namespace user-apps \
  --watch 60
```

### Status and Monitoring

#### Check VM Status (without changing affinity)

```bash
# Show current CPU assignments without making changes
sudo ./adv-core-pinning.sh check --vm1 ub22-vm --vm2 win11-vm --namespace user-apps
```

#### View Logs

```bash
# View syslog entries
sudo journalctl -t vcpu-pinning -f

# Or view system logs
sudo tail -f /var/log/syslog | grep vcpu-pinning
```

## CPU List Formats

The script supports two CPU specification formats:

### Range Format

```bash
--cpu1 0-3    # CPUs 0, 1, 2, 3 (inclusive)
--cpu1 4-7    # CPUs 4, 5, 6, 7 (inclusive)
```

### List Format

```bash
--cpu1 0,2,4,6    # CPUs 0, 2, 4, 6
--cpu1 1,3,5,7    # CPUs 1, 3, 5, 7
```

## Monitoring Features

### Automatic Restart Detection

- Monitors VM process IDs (PIDs)
- Detects when VMs restart (PID changes)
- Automatically reapplies CPU pinning after restart
- Logs all restart events

### Thread Count Monitoring

- Tracks vCPU thread count changes
- Detects VM reconfiguration (CPU count changes)
- Adapts CPU pinning to new thread counts

### Continuous Monitoring

- Configurable watch intervals
- Persistent CPU affinity enforcement
- Graceful shutdown handling
- Comprehensive error reporting

### Daemon Status Management

- **PID File Management**: Creates and manages PID files in `/var/run/`
- **Graceful Shutdown**: Handles SIGTERM for clean shutdown
- **Status Monitoring**: Check daemon health and recent activity
- **Process Information**: View daemon runtime statistics
- **Log Integration**: Recent log entries displayed with status
- **Automatic Cleanup**: Removes stale PID files

## Operational Modes

### Interactive Mode (Default)

- Normal terminal output
- Real-time status updates
- Suitable for testing and debugging

### Daemon Mode (`--daemon`)

- Background operation
- No terminal output
- Logs to syslog
- Creates PID file in `/var/run/`
- Suitable for production deployment

### Single Run Mode (`--watch 0`)

- Execute once and exit
- No continuous monitoring
- Suitable for one-time operations

### Starting a Daemon

```bash
# Start daemon for dual VM monitoring
sudo ./adv-core-pinning.sh start \
  --vm1 ub22-vm --cpu1 0-2 \
  --vm2 win11-vm --cpu2 4-6 \
  --namespace user-apps \
  --watch 60 \
  --daemon
```

### Checking Daemon Status

```bash
# Check if daemon is running
sudo ./adv-core-pinning.sh status --vm1 ub22-vm --vm2 win11-vm

# Example output:
# Daemon is running (PID: 12345)
# PID file: /var/run/vcpu-pinning-ub22-vm-win11-vm.pid
# Process info:
#   12345  1234 vcpu-pinning-daemon...  5:23  0.1  0.2
# Recent log entries:
#   [2025-07-11 10:30:15] [INFO] Starting VM monitoring service
#   [2025-07-11 10:30:16] [INFO] CPU affinity set for 3/3 threads...
```

### Stopping a Daemon

```bash
# Gracefully stop daemon
sudo ./adv-core-pinning.sh stop --vm1 ub22-vm --vm2 win11-vm

# Example output:
# Stopping daemon (PID: 12345)...
# Daemon stopped successfully
```

### Restarting a Daemon

```bash
# Restart with new settings
sudo ./adv-core-pinning.sh restart \
  --vm1 ub22-vm --cpu1 0-3 \
  --vm2 win11-vm --cpu2 4-7 \
  --namespace user-apps \
  --watch 30

# Example output:
# Restarting daemon...
# Stopping daemon (PID: 12345)...
# Daemon stopped successfully
# Starting daemon...
# Daemon restarted successfully
```

### PID File Location

Daemon PID files are stored in `/var/run/` with the format:

- Single VM: `/var/run/vcpu-pinning-<vm1_name>.pid`
- Dual VM: `/var/run/vcpu-pinning-<vm1_name>-<vm2_name>.pid`

### Daemon Features

- **Graceful Shutdown**: Responds to SIGTERM and SIGINT signals
- **Automatic Cleanup**: Removes PID files on exit
- **Health Monitoring**: Built-in status checking
- **Syslog Integration**: All activities logged to system log
- **Process Management**: Proper daemon process handling

## Production Deployment

### Systemd Service

Create a systemd service for automatic startup:

```ini
# /etc/systemd/system/vcpu-pinning.service
[Unit]
Description=vCPU Core Pinning Service
After=kubelet.service

[Service]
Type=forking
ExecStart=/path/to/adv-core-pinning.sh --vm1 ub22-vm --cpu1 0-2 --vm2 win11-vm --cpu2 4-6 \
--namespace user-apps --watch 60 --daemon
PIDFile=/var/run/vcpu-pinning-ub22-vm-win11-vm.pid
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable vcpu-pinning.service
sudo systemctl start vcpu-pinning.service
```

### Monitoring and Logging

```bash
# Check service status
sudo systemctl status vcpu-pinning.service

# View logs
sudo journalctl -u vcpu-pinning.service -f

# View script-specific logs
sudo journalctl -t vcpu-pinning -f
```

## Troubleshooting

### Common Issues

#### VM Not Found

```bash
# Check if VM exists
sudo ./adv-core-pinning.sh check --vm1 your-vm-name

# List all QEMU processes
ps -ef | grep qemu | grep guest=
```

#### Permission Denied

```bash
# Ensure running with sudo
sudo ./adv-core-pinning.sh start --vm1 your-vm-name --cpu1 0-3
```

#### Invalid CPU List

```bash
# Check available CPUs
nproc --all
lscpu

# Use valid CPU range
sudo ./adv-core-pinning.sh start --vm1 your-vm-name --cpu1 0-$(($(nproc --all) - 1))
```

#### Daemon Management Issues

```bash
# Check daemon status
sudo ./adv-core-pinning.sh status --vm1 your-vm-name

# Force stop if daemon is unresponsive
sudo pkill -f "vcpu-pinning-daemon"
sudo rm -f /var/run/vcpu-pinning-*.pid

# Check for stale PID files
ls -la /var/run/vcpu-pinning-*.pid
```

### Debug Mode

Add debug output by modifying the script:

```bash
# Enable bash debug mode
bash -x ./adv-core-pinning.sh start --vm1 your-vm-name --cpu1 0-3
```

### Manual Daemon Management

```bash
# Find daemon process
ps aux | grep vcpu-pinning-daemon

# Check PID file
cat /var/run/vcpu-pinning-vm1-vm2.pid

# Kill daemon manually
sudo kill $(cat /var/run/vcpu-pinning-vm1-vm2.pid)

# Check logs
sudo journalctl -t vcpu-pinning -f
# or
sudo tail -f /var/log/syslog | grep vcpu-pinning
```

## Performance Considerations

### CPU Affinity Benefits

- **Reduced context switching**: Threads stay on assigned cores
- **Improved cache locality**: Better CPU cache utilization
- **Predictable performance**: Consistent CPU allocation
- **Resource isolation**: Prevent VM interference

### Best Practices

1. **Separate physical cores**: Assign VMs to different physical cores
2. **NUMA awareness**: Keep VMs within same NUMA node when possible
3. **Avoid system cores**: Reserve some cores for host OS
4. **Monitor performance**: Use system monitoring tools to verify benefits

### Example NUMA-Aware Configuration

```bash
# Check NUMA topology
numactl --hardware

# Pin VMs to different NUMA nodes
sudo ./adv-core-pinning.sh \
  --vm1 vm-numa0 --cpu1 0-7 \
  --vm2 vm-numa1 --cpu2 8-15 \
  --watch 60
```

## Security Considerations

- **Root privileges required**: Script needs sudo for taskset operations
- **PID file security**: PID files created in `/var/run/`
- **Syslog logging**: All operations logged for audit trail
- **Process isolation**: Each VM's threads managed independently

## Logging

The script provides comprehensive logging:

### Log Levels

- **INFO**: Normal operations, status updates
- **WARN**: Non-critical issues, warnings
- **ERROR**: Critical errors, failures

### Log Destinations

- **Console**: Interactive mode output
- **Syslog**: System-wide logging (always enabled)
- **Journald**: Systemd journal integration

### Example Log Entries

```bash
[2025-07-11 10:30:15] [INFO] Starting VM monitoring service
[2025-07-11 10:30:15] [INFO] VM1: ub22-vm (CPUs: 0-2)
[2025-07-11 10:30:15] [INFO] VM2: win11-vm (CPUs: 4-6)
[2025-07-11 10:30:16] [INFO] VM 'ub22-vm' found in namespace 'user-apps' with PID: 170772 (threads: 3)
[2025-07-11 10:30:16] [INFO] CPU affinity set for 3/3 threads of VM 'ub22-vm' (CPUs: 0 1 2)
[2025-07-11 10:35:20] [INFO] VM restart detected for 'ub22-vm': PID changed from 170772 to 171234
```

## Contributing

Feel free to submit issues and enhancement requests!

## License

This script is provided as-is for educational and production use.

---

**Note**: This script requires root privileges for CPU affinity operations.
Always test in a development environment before production deployment.
