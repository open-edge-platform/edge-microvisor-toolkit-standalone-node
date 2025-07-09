# SPDX-FileCopyrightText: (C) 2025 Intel Corporation

# SPDX-License-Identifier: Apache-2.0

# README

This directory provides the necessary resources to:

- Download k3s artifacts for the Standalone Edge Node installer.
- Build the Standalone Edge Node installer for k3s.
- Execute the installer to deploy the k3s stack and extensions on a Microvisor Edge Node.
- Manage the Standalone Edge Node k3s stack, including viewing dashboards, managing pods, and installing applications.

**Note:** Upgrades from version 3.0 to 3.1 are not supported due to the transition from RKE2 to k3s.

For detailed instructions, refer to:

- [Standalone Edge Node Installer Guide](./docs/standalone-edge-node-installer.md)
- [Development Machine Usage Guide](./development-machine-usage.md)

For customizing the default CNI refer to the [k3s documentation](https://docs.k3s.io/networking/basic-network-options#flannel-options)
