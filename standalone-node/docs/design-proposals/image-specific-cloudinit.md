# Design Proposal: Cloud init configuration specific to an image

Author(s): Krishna, Shankar

Last updated: 04/06/2025

## Abstract

The Edge Microvisor Toolkit Standalone Node (EMT-S) ensures simplified edge node deployment.
There are use cases where customers would like their own custom image of EMT to be deployed and
configured as part of the provisioning.

To accommodate this use case, the EMT-S installer will include a configuration section for
users to update before creating a bootable USB drive. The configuration section will be used to update the
`cloud-init` template for the specific EMT image. The configuration can span across OS and Kubernetes.

## Proposal

To deploy the standalone node, user needs to configure settings in the
[config-file](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/blob/main/standalone-node/installation_scripts/config-file),
required for creation of a bootable USB drive.

The proposal is to include a dedicated `cloud-init` section in the configuration file. It will let users easily customize
the `cloud-init` configuration for their EMT image, such as installing extra packages, enabling services, or running custom
scripts.

- Any changes made in the `cloud-init` section will be automatically applied to the `cloud-config` file located in
    `/etc/cloud` on the EMT image during provisioning.
- After provisioning, the EMT image will include all user-specified packages and settings.

Below is a sample of the new `cloud-init` section in config-file. Users can edit this section to fit their needs.

## Custom Cloud-Init Section Example

```yaml
#cloud-config

# === Enable or disable systemd services ===
# List services to enable or disable.
# Note : Make sure Services should be part of the Base Image to enable or disable.
# Example:
#   services:
#     enable: [docker, ssh]
#     disable: [apache2]
services:
    enable: []
    disable: []

# === Create custom configuration files ===
# To create a file, specify its path,permission and content.
# Note : you can create as many files (shell,text,yaml) as you wish, just expand the write_files: with prefix -path for next file
# Note : Make sure scripts/files passing to cloud-init file well tested, if any issues in the script/file error messages
#        will be present under /var/log/cloud-init-output.log file on EMT image.
# Example:
#   write_files:
#     - path: /etc/cloud/test.sh
#        permissions: '0644'
#       content: |
#         #!/bin/sh
#         echo "This is Example"
write_files: []

# === Custom run commands ===
# List commands or scripts to run at boot.
# Note : Make sure syntax is correct for the commands, if any issues in commands error messages will be present
#        under /var/log/cloud-init-output.log file on EMT image.
# Example:
#   runcmd:
#     - systemctl restart myservice
#     - bash /etc/cloud/test.sh
runcmd: []

```

## User Experience

- User creates a bootable USB drive.
- During creation, the user edits config-file and updates the custom `cloud-init` section as needed.
- On boot, the installer reads the custom `cloud-init` section and provisions the EMT host accordingly.
- If invalid values are provided, provisioning may succeed, but the `cloud-init` changes may not be applied correctly on
  first boot.

## Default Behavior

- The custom `cloud-init` section is **optional**.
- Users can update the section to customize the `cloud-init` file as needed, or skip it to use the default settings.
