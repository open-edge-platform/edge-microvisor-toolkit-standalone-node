# Design Proposal: LVM configuration enhancement

Author(s): Krishna, Shankar

Last updated: 13/06/2025

## Abstract

The Edge Microvisor Toolkit Standalone (EMT-S) streamlines the deployment of Edge Microvisor Toolkit (EMT) nodes.
However, some deployment environments require flexibility due to limited storage capacities.
The current implementation statically allocates 100G to the root partition if only a single disk is present, assigning
the remaining disk space to the LVM partition.

This proposal introduces an enhancement to allow users to allocate 0 GB or any desired greater value for the LVM
partition during creation of a bootable USB drive.
This change increases adaptability and ensures optimal utilization of available storage resources.

## Proposal

To deploy the standalone node, user needs to configure settings in the
[config-file](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/blob/main/standalone-node/installation_scripts/config-file),
required for creation of a bootable USB drive.

The proposal is to improve the current configuration mechanism by allowing users to set the LVM partition size
if only a single disk is present on the edge node. to maximize disk size for the persistent partition.
If multiple disks are present, the LVM partition will be created on secondary disks (other than the rootfs disk).

The following script can be used as a new section in the config-file:

```bash
# ------------------ LVM partition size ------------------------
# Set the LVM partition size in GB. This will be used for creating
# the LVM partition that will be used for user data. By default,
# `lvm_size_ingb` will be set to ZERO. Update the size in GB if required.
# Example: lvm_size_ingb="20"

# Note: If the Edge Node has only a single hard disk, update the lvm_size_ingb value; otherwise, skip it.
lvm_size_ingb="0"
```

## User Experience

When [creating a bootable USB drive](../user-guide/get-started-guide.md#create-bootable-usb-from-source-code),
for a single disk edge node, you need set the desired LVM partition size in the
[config file](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/blob/main/standalone-node/installation_scripts/config-file).
On boot, the LVM partition is set to the specified size and the EMT host is provisioned accordingly.

## Default Behavior

- By default, for single disk edge nodes, the **LVM partition size is set to zero** if no input is provided.
- There is no need to update `lvm_size_ingb` for multiple disk edge nodes. It will be ignored
  regardless of any provided value, as the LVM partition will be created on a secondary disk.
