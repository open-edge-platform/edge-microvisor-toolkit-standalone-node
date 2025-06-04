# Design Proposal: Cloud init configuration specific to an image

Author(s): Krishna, Shankar

Last updated: 04/06/2025

## Abstract

The Edge Microvisor Toolkit Standalone (EMT-S) provides a simplified approach to deploying an Edge Microvisor Toolkit
(EMT) edge. There are use cases where customers would like to use their own image of EMT to be deployed and
configured as part of the provisioning.

To enable this use case, going forward EMT-S installer will support a configuration section that is available for
the user to update before creating the bootable USB. The configuration section will be used to update the
`cloud-init` template for the EMT image that is being provisioned. The configuration can span across kernel,
OS, and Kubernetes.

## Proposal
