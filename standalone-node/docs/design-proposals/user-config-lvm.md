# Design Proposal: LVM configuration enhancement

Author(s): Krishna, Shankar

Last updated: 13/06/2025

## Abstract

The Edge Microvisor Toolkit Standalone (EMT-S) streamlines the deployment of Edge Microvisor Toolkit (EMT) nodes.
However, some deployment environments require flexibility due to limited storage capacities.
The current implementation statically allocates 100G to the root partition if only a single disk is present, assigning
the remaining disk space to the LVM partition.

This proposal introduces an enhancement to allow user-configurable LVM partition sizing during the EMT-S USB installer
creation process. Users will be able to specify the desired size of the LVM partition—including the option to allocate
0G or any value greater—based on their deployment needs.
This change increases adaptability and ensures optimal utilization of available storage resources.

## Proposal

Edge Microvisor Toolkit Standalone uses the
[config file](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/blob/main/standalone-node/installation_scripts/config-file)
to take user inputs during bootable USB creation.
These inputs are used to configure settings during the EMT provisioning process.

The proposal is to extend the current user input configuration mechanism to allow users to set the LVM partition size
if only a single disk is present on the Edge Node, ensuring the persistent partition gets the maximum disk size.
If multiple disks are present, the LVM partition will be created on secondary disks (other than the rootfs disk).

This can be a new section in the config file:

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

- User creates a bootable USB using the EMT-S USB Installer.
- During creation, the user edits the config file and updates the LVM partition size as needed in case of a single disk.
- On boot, the installer reads the config file's LVM partition section and provisions the EMT host accordingly.

## Default Behavior

- By default, for single disk Edge Nodes, the LVM size is set to ZERO if no input is provided.
- For multiple disk Edge Nodes, there is no need to update `lvm_size_ingb` (it will be ignored even value provided),as
  the LVM partition will be created on a secondary disk.
