<!--
SPDX-FileCopyrightText: (C) 2025 Intel Corporation
SPDX-License-Identifier: Apache-2.0

# User App Folder

This folder allows users to store application artifacts, such as container images and Helm charts. 
All files placed here will be copied to the persistent volume on the Edge node at `/opt/user-apps`.

To copy,configure, or launch your applications, use the custom `cloud-init` section available in the configuration file.

- Store your application files in this folder.
- Update the `cloud-init` section as needed to automate deployment.

