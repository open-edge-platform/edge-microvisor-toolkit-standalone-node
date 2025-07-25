# Edge Microvisor Toolkit Standalone Node - User Guide

Welcome to the comprehensive user guide for the Edge Microvisor Toolkit (EMT) Standalone Node.
This documentation will help you get started, customize your deployment, and manage your edge
infrastructure effectively.

## What is EMT Standalone Node?

The Edge Microvisor Toolkit Standalone Node is a complete edge computing solution that provides:

- **Immutable edge-optimized operating system** built on Intel Architecture
- **Lightweight Kubernetes (k3s)** for container orchestration
- **Desktop virtualization capabilities** for VM-based workloads
- **Easy deployment and management** tools for edge environments

## Documentation Overview

This user guide is organized into focused sections to help different types of users find the information they need quickly.

### 📚 Documentation Structure

| Guide | Purpose | Target Audience | Time Required |
|-------|---------|-----------------|---------------|
| [Quick Start Guide](quick-start-guide.md) | Get your first node running quickly | New users, evaluators | 30-60 minutes |
| [Complete Setup Guide](complete-setup-guide.md) | Comprehensive installation and configuration | System administrators | 2-3 hours |
| [Desktop Virtualization Guide](desktop-virtualization-guide.md) | Enable VM workloads with GPU support | Advanced users, VM deployments | 1-2 hours |
| [Pre-loading Applications](pre-loading-user-apps.md) | Deploy applications during installation | OEMs, automated deployments | 1-2 hours |
| [Update and Maintenance](update-and-maintenance-guide.md) | Keep your system current and healthy | Operations teams | 30 minutes |
| [Troubleshooting Guide](troubleshooting-guide.md) | Resolve common issues | All users | As needed |

### 🎯 Choose Your Path

**👋 New to EMT?** Start with the [Quick Start Guide](quick-start-guide.md) to get your first node running in under an hour.

**🔧 Need full control?** The [Complete Setup Guide](complete-setup-guide.md) covers all
configuration options and advanced scenarios.

**💻 Running VMs?** Check out the [Desktop Virtualization Guide](desktop-virtualization-guide.md)
for GPU passthrough and display virtualization.

**🏭 Enterprise deployment?** See [Pre-loading Applications](pre-loading-user-apps.md) for
automated application deployment.

## Prerequisites

Before starting with any guide, ensure you have:

### Required Knowledge

- **Linux command line** - Basic familiarity with terminal commands
- **Networking basics** - Understanding of IP addresses, subnets, and routing
- **Container concepts** - Basic knowledge of containers and Kubernetes (helpful but not required)

### Hardware Requirements

- **Intel Architecture platform** (See [supported processors](../../../README.md#supported-processor-families))
- **8GB RAM minimum** (16GB+ recommended for virtualization)
- **128GB storage** (SSD recommended)
- **Wired Ethernet connection**
- **USB drive** (8GB minimum for installer)

### Software Requirements

- **Linux development system** for creating bootable USB
- **SSH client** for remote management
- **Web browser** for accessing web interfaces

## Glossary

| Term | Definition |
|------|------------|
| **EMT** | Edge Microvisor Toolkit - The core operating system |
| **k3s** | Lightweight Kubernetes distribution used in EMT |
| **Cloud-init** | System initialization and configuration tool |
| **Immutable OS** | Read-only operating system that requires image updates |
| **A/B Update** | Dual-partition update system for safe OS updates |
| **SR-IOV** | Single Root I/O Virtualization for hardware sharing |
| **Desktop Virtualization** | Running desktop VMs with GPU acceleration |
| **NAD** | Network Attachment Definition for additional network interfaces |

## Getting Help

### Common Issues

Check the [Troubleshooting Guide](troubleshooting-guide.md) for solutions to common problems.

### Log Locations

- **Installation logs**: `/var/log/os-installer.log`
- **Cloud-init logs**: `/var/log/cloud-init-output.log`
- **Kubernetes logs**: `journalctl -u k3s`
- **System logs**: `journalctl -f`

### Community Support

- **GitHub Issues**: [Report bugs and request features](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/issues)
- **Documentation**: This guide and the main [README](../../../README.md)

## What's Next?

Ready to get started? Choose your path:

- **Quick evaluation**: [Quick Start Guide](quick-start-guide.md)
- **Production deployment**: [Complete Setup Guide](complete-setup-guide.md)
- **VM workloads**: [Desktop Virtualization Guide](desktop-virtualization-guide.md)

---

**Last updated:** July 25, 2025
