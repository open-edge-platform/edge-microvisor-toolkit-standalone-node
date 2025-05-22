# Edge Microvisor Toolkit Standalone Node

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/badge)](https://scorecard.dev/viewer/?uri=github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node)

## Overview

The Standalone Node solution, designed to enable Edge AI applications evaluation on Intel platform
is designed to empower enterprise customers and developers by providing a rapid and efficient
means to familiarize, evaluate, and trial Edge AI applications on Intel Architecture-based platforms.
This comprehensive solution stack includes the edge-optimized immutable Edge Microvisor Toolkit,
integrated with Kubernetes and foundational extensions, enabling the deployment of both cloud-native
and legacy VM-based applications.

## Get Started

The repository comprises the following components.

HookOS: contains the Tinkerbell installation environment for bare-metal. It runs in-memory, installs operating system, and handles deprovisioning.

Edge Microvisor Toolkit: Edge Microvisor toolkit immutable non-RT image as  hypervisor.

Kubernetes Cluster: The Kubernetes RKE2 cluster is deployed along the cluster extensions

For more details refer to [Get Started Guide](docs/user-guide/Get-Started-Guide.md).

## Develop

To develop one of the Managers, please follow its guide in README.md located in its respective folder.

## Contribute

To learn how to contribute to the project, see the Contributor's Guide.

## Community and Support

To learn more about the project, its community, and governance, visit the Edge Orchestrator Community.

For support, start with Troubleshooting

## License

Each component of the Edge Infrastructure onboarding is licensed under Apache 2.0.
Last Updated Date: May 22, 2025
