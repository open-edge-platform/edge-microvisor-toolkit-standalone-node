# Edge Microvisor Toolkit Standalone Node

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/badge)](https://scorecard.dev/viewer/?uri=github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node)

## Overview

The Edge Microvisor Toolkit Standalone Node solution, designed to enable Edge AI applications evaluation on Intel platforms is designed to empower enterprise customers and developers by providing a rapid and efficient means to familiarize, evaluate, and trial Edge AI applications on Intel Architecture-based platforms. This comprehensive solution stack includes the edge-optimized immutable Edge Microvisor Toolkit,
integrated with Kubernetes and foundational extensions, enabling the deployment of both cloud-native and legacy VM-based applications.

Key Features:

- Edge Optimized Immutable Toolkit: The Edge Microvisor Toolkit is specifically optimized for edge environments, ensuring robust
performance on Intel Architecture-based platforms and security.
- Kubernetes Integration: Seamlessly deploy and manage applications using Kubernetes and cloud-native tools.
- Foundational Extensions: These extensions support the deployment of diverse application types, including both modern cloud-native and traditional VM-based applications.

Upon completion of the evaluation using the Edge Microvisor Toolkit Standalone Node solution, designed to enable
Edge AI applications evaluation on Intel platforms customers will gain critical insights into the capabilities of edge platforms and Edge AI applications. This knowledge is essential for deploying use-case-specific applications and will significantly aid in scaling out deployments.

## How It Works

To begin the evaluation process, the customer downloads the Edge Microvisor Toolkit Standalone Node installer to their laptop or development system. This system will be used to create a bootable USB installer for the edge node designated for evaluation. During this stage, the customer can configure settings such as proxy and user credentials.

Next, the customer runs the automated installer, which generates a bootable USB stick. This USB stick is self-contained and includes all the necessary software components to install the Edge Microvisor Toolkit, Kubernetes, foundational Kubernetes extensions, and the Kubernetes Dashboard.

With the bootable USB stick prepared, the customer can proceed to install it on the edge node.

Once the edge node is up and running, the customer evaluates various Edge AI applications, pipelines, and microservices available from the Intel Edge services catalog and open-source repositories using standard tools like `helm`.

System requirements for the hardware and software requirements Edge Microvisor Toolkit Standalone Node is designed to support all Intel® platforms with the latest Intel® kernel to ensure all features are exposed and available for application and workloads. The microvisor has been validated on the following platforms.

![How it works](standalone-node/images/howitworks.png)  

### System Requirements

The Edge Microvisor Toolkit Standalone Node solution is engineered to support a diverse range of Intel® platforms, ensuring compatibility and optimal performance. Below is a detailed summary of the supported processor families and system requirements:

#### Supported Processor Families

| Processor Family            | Supported Models                                                                |
|-----------------------------|---------------------------------------------------------------------------------|
| **Intel Atom® Processors**  | Intel® Atom® X Series                                                           |
| **Intel® Core™ Processors** | 12th Gen Intel® Core™, 13th Gen Intel® Core™, Intel® Core™ Ultra (Series 1)     |
| **Intel® Xeon® Processors** | 4th Gen Intel® Xeon® SP, 3rd Gen Intel® Xeon® SP                                |

#### Memory, Storage and Networking Requirements

| Component      | Minimum Requirements           |
|----------------|--------------------------------|
| **RAM**        | 8GB                            |
| **Storage**    | 128GB SSD/HDD or NVMe          |
| **Networking** | Wired Ethernet                 |
| **GPU**        | Integrated GPU (i915)          |

## Get Started

The repository comprises the following components.

* [**HookOS**](standalone-node/hook_os/): contains the Tinkerbell installation environment for bare-metal. It runs in-memory, installs operating system, and handles deprovisioning.

* [**Edge Microvisor Toolkit**](standalone-node/host_os/): Edge Microvisor toolkit immutable non-RT image as  hypervisor.

* [**Kubernetes Cluster**](standalone-node/cluster_installers): The Kubernetes RKE2 cluster is deployed along the cluster extensions.

For more details refer to [Get Started Guide](standalone-node/docs/user-guide/Get-Started-Guide.md).

## Getting Help

If you encounter bugs, have feature requests, or need assistance,
[file a GitHub Issue](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/issues).

Before submitting a new report, check the existing issues to see if a similar one has not
been filed already. If no matching issue is found, feel free to file the issue as described
in the [contribution guide](./standalone-node/docs/contribution.md).

For security-related concerns, please refer to [SECURITY.md](./SECURITY.md).

## Develop

To develop an Edge Microvisor Toolkit Standalone Node, you'll need to follow the instructions provided in the [Get Started Guide](standalone-node/docs/user-guide/Get-Started-Guide.md) located in its respective folder.

## Contribute

To learn how to contribute to the project, see the [Contributor's Guide](standalone-node/docs/contribution.md).

## Community and Support

To learn more about the project, its community, and governance, visit the Edge Orchestrator Community.

For support, see the [Troubleshooting section of the Get Started Guide](standalone-node/docs/user-guide/Get-Started-Guide.md#troubleshooting).

## License

Each component of the Edge Microvisor Toolkit Standalone Node is licensed under [Apache 2.0][apache-license].

Last Updated Date: May 22, 2025

[apache-license]: https://www.apache.org/licenses/LICENSE-2.0
