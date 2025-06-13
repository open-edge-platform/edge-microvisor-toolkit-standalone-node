# Design Proposal: LVM configuration enhancement

Author(s): Krishna, Shankar

Last updated: 13/06/2025

## Abstract

The Edge Microvisor Toolkit Standalone (EMT-S) streamlines the deployment of Edge Microvisor Toolkit (EMT) nodes.
However, some deployment environments require flexibility due to limited storage capacities.
The current implementation statically allocates 100G to the root partition, assigning the remaining disk
space to the LVM partition.

This proposal introduces an enhancement to allow user-configurable LVM partition sizing during the EMT-S USB
installer creation process. Users will be able to specify the desired size of the LVM partition—including the
option to allocate 0G or any value greater—based on their deployment needs. This change increases adaptability
and ensures optimal utilization of available storage resources.

## Proposal

Edge Microvisor Toolkit Standalone uses the [config](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/blob/main/standalone-node/installation_scripts/config-file)
file to take user inputs during bootable USB creation. This user input will be used to configure setting during the EMT
provisioning process.

The proposal is to extend the current user input configuration mechanism to allow users to set the LVM partition size.
This can be a new section like below:

```bash
# ------------------ LVM partition size ------------------------
# Set the LVM partition size in G. This will be used for creating
# the LVM partition that will be used for user data. By default, 
# `lvm_size_ingb` will be set to Total hard drive size minus 100G.
# Example: lvm_size_ing="20" or lvm_size_ingb="0"
lvm_size_ingb=""
```
