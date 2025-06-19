# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# README

This directory contains scripts, artifacts and documentation necessary to:
- download k3s artifacts for Standalone Edge Node installer
- build the k3s Standalone Edge Node installer
- run the installer and install the k3s stack and the extension on a Microvisor Edge Node
- perform operations on the Standalone Edge Node k3s stack - view dashboard, pods and install applications

**Note** Upgrades from 3.0 to 3.1 are not supported as the distribution changed from RKE2 to k3s.

For detailed instructions follow:

- [Standalone Edge Node installer](./docs/standalone-edge-node-installer.md)
- [Using SEN from development machine](./development-machine-usage.md)
