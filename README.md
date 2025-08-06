# Edge Microvisor Toolkit Standalone Node

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/badge)](https://scorecard.dev/viewer/?uri=github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node)

## Overview

The Edge Microvisor Toolkit Standalone Node solution is designed to empower developers and
enterprise customers by allowing for efficient trials and evaluation of Edge AI applications
on Intel Architecture-based platforms. This comprehensive solution stack includes the
edge-optimized immutable Edge Microvisor Toolkit integrated with K3s Kubernetes and foundational
extensions, which enables deployment of both cloud-native and legacy VM-based applications.

### Key Features

- **Edge Optimized Immutable Toolkit:** The Edge Microvisor Toolkit is specifically optimized
  for edge environments, ensuring security and robust performance on Intel Architecture-based
  platforms.
- **Kubernetes Integration:** Seamlessly deploy and manage applications using Kubernetes and
  cloud-native tools.
- **Foundational Extensions:** These extensions support the deployment of diverse application
  types, including both modern cloud-native as well as traditional VM-based applications.
- **Easy Evaluation:** The Edge Microvisor Standalone Node allows for critical insights into
  the capabilities of Edge AI solutions, which is beneficial for deployments of
  use-case specific applications and potential scale outs.

## System Requirements

The Edge Microvisor Toolkit Standalone Node solution is engineered to support a diverse
range of Intel® platforms, ensuring compatibility and optimal performance. Below is a
detailed summary of the supported processor families and system requirements:

### Supported CPUs

| Processor Family            | Supported Models                                                                |
|-----------------------------|---------------------------------------------------------------------------------|
| **Intel Atom® Processors**  | Intel® Atom® X Series                                                           |
| **Intel® Core™ Processors** | 12th Gen Intel® Core™, 13th Gen Intel® Core™, Intel® Core™ Ultra (Series 1)     |
| **Intel® Xeon® Processors** | 5th Gen Intel® Xeon® SP, 4th Gen Intel® Xeon® SP, 3rd Gen Intel® Xeon® SP       |

### Memory, Storage and Networking Requirements

| Component      | Minimum Requirements           |
|----------------|--------------------------------|
| **RAM**        | 8GB                            |
| **Storage**    | 128GB SSD/HDD or NVMe          |
| **Networking** | Wired Ethernet                 |
| **GPU**        | Integrated GPU (i915)          |

## Get Started

The repository comprises the following components.

- [**Edge Microvisor Bootkit**](standalone-node/emt_uos): Includes scripts for downloading the minimal
  build of the Edge Microvisor Toolkit, which acts as an installation environment for bare-metal systems.
  It operates in RAM, installs the operating system, and manages provisioning.
  For further information on Bootkit, please consult
  [the documentation](https://github.com/open-edge-platform/edge-microvisor-toolkit/blob/3.0/docs/developer-guide/emt-bootkit.md).

- [**Edge Microvisor Toolkit**](standalone-node/host_os/): The Edge Microvisor Toolkit's non-real-time
  image is immutable and functions as a hypervisor. The scripts available here will download this
  immutable Edge Microvisor Toolkit non-RT image.  For further information on Edge Microvisor Toolkit,
  please consult [the documentation](https://github.com/open-edge-platform/edge-microvisor-toolkit/blob/3.0/README.md)

- [**Provisioing Scripts**](standalone-node/provisiong_scripts): This folder contains provisioning scripts
  for the Edge Microvisor Toolkit, as well as the installation and configuration of the K3s Kubernetes
  cluster with its extensions.

  > **Note** The 3.1 version does not support updating from 3.0 due to the change in
    kubernetes distribution.

For more details refer to [Get Started Guide](standalone-node/docs/user-guide/get-started-guide.md).

## How It Works

To start the evaluation process, the customer compiles the Edge Microvisor Toolkit Standalone
Node source code to create a USB bootable installer image for the edge node intended for evaluation.
At this stage, the customer has the option to configure settings like proxy and user credentials.

Next, the customer runs the automated installer, which generates a bootable USB drive. This USB
drive is self-contained and includes all the necessary software components to install the
Edge Microvisor Toolkit, Kubernetes, foundational Kubernetes extensions, and the Kubernetes Dashboard.

With the bootable USB drive prepared, the customer can proceed to install it on the edge node.

Once the edge node is up and running, the customer evaluates various Edge AI applications,
pipelines, and microservices available from the Intel Edge services catalog and open-source
repositories using standard tools like `helm`.

Edge Microvisor Toolkit Standalone Node is designed to support all Intel® platforms with the
latest Intel® kernel to ensure all features are exposed and available for application and workloads.

![How it works](standalone-node/images/Demo-presentation.gif)

## Getting Help

If you encounter bugs, have feature requests, or need assistance,
[file a GitHub Issue](https://github.com/open-edge-platform/edge-microvisor-toolkit-standalone-node/issues).

Before submitting a new report, check the existing issues to see if a similar one has not
been filed already. If no matching issue is found, feel free to file the issue as described
in the [contribution guide](./standalone-node/docs/contribution.md).

For security-related concerns, refer to [SECURITY.md](./SECURITY.md).

## Develop

To develop an Edge Microvisor Toolkit Standalone Node, you will need to follow the instructions
provided in the [Get Started Guide](standalone-node/docs/user-guide/get-started-guide.md).

## Contribute

To learn how to contribute to the project, see the [Contributor's Guide](standalone-node/docs/contribution.md).

## Community and Support

To learn more about the project, its community, and governance, visit the Edge Orchestrator Community.

For support, see the [Troubleshooting section of the Get Started Guide](standalone-node/docs/user-guide/Get-Started-Guide.md#troubleshooting).

## License

Each component of the Edge Microvisor Toolkit Standalone Node is licensed under [Apache 2.0][apache-license].

Last Updated Date: July 14, 2025

[apache-license]: https://www.apache.org/licenses/LICENSE-2.0
