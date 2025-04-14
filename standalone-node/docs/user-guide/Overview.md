# Edge Microvisor Toolkit Standalone Node

Setting Up an Edge Microvisor Toolkit on a Standalone Node with a Single-Node Cluster Using a USB Bootable Flash Drive


## Overview
The following article provides information about the Edge Microvisor Toolkit for Standalone Node installation including system requirements.


The Edge Microvisor Toolkit Standalone is a comprehensive package that includes the immutable Edge Microvisor Toolkit, along with the installation of Kubernetes and  all necessary extensions to establish a fully functional single-node cluster. Edge Microvisor Toolkit is a streamlined container operating system that showcases the Intel silicon optimizations. Built on Azure Linux, it features a Linux Kernel maintained by Intel, incorporating all the latest kernel and user
patches. 

![Overview](_images/overview.png)

## How It Works
The Edge Microvisor Toolkit is installed on the standalone edge node along with kubernetes cluster using a bootable USB drive created from this installer. The Edge Microvisor Toolkit standalone Node can be used to deploy user applications using helm charts onto the edge node for the evaluation.

### Getting Started

System requirements for the hardware and software requirements Edge Microvisor Toolkit Standalone is designed to support all Intel® platforms with the latest Intel® kernel to ensure all features are exposed and available for application and workloads. The microvisor has been validated on the following platforms.

### System Requirements

|      Atom             |               Core            |      Xeon               |
| ----------------------| ----------------------------- | ----------------------- |
| Intel® Atom® X Series | 12th Gen Intel® Core™         | 4th Gen Intel® Xeon® SP |
|                       | 13th Gen Intel® Core™         | 3rd Gen Intel® Xeon® SP |
|                       | Intel® Core™ Ultra (Series 1) |                         |

The following outlines the recommended hardware configuration to run Edge Microvisor Toolkit.

| Component    | Standalone Installation    |
|--------------|----------------------------|
| CPU          | Intel® Atom®, Intel® Core™, Intel® Core Ultra™ or Intel® Xeon®|
| RAM          | 8GB minimum                |
| Storage      | 128GB SSD/NVMe or eMMC      |
| Networking   | 1GbE Ethernet or Wi-Fi     |

## Installation Instructions

### Step 1: Prerequisites

- Your development system should be running a Ubuntu 22.04 machine.
- Internet connectivity is available on the system.
- The target node(s) hostname must be in lowercase, numerals, and hyphen’ – ‘.
- For example: wrk-8 is acceptable; wrk_8, WRK8, and Wrk^8 are not accepted as
hostnames.
- Required proxy settings must be added to the /etc/environment file (more below).
- Get access to the [Edge Software Catalog](https://edgesoftwarecatalog.intel.com/) portal
- Refer to Get Started Guide [Get Started Guide](https://docs.edgeplatform.intel.com/standalone-edge-node/user-guide/Get-Started-Guide.html) for comprehensive steps on configuring the Standalone Node.

### Step 2: Download the ESC Package

Select Configure & Download to download the Intel® Edge Microvisor Toolkit
Standalone Node package [Configure & Download](https://edge-services-catalog-prod-qa.apps1-bg-int.icloud.intel.com/package/edge_microvisor_toolkit_standalone_node)

### Step 3: Configure

The ESC Package will be downloaded on your Local System in a zip format, labeled as `Edge_Microvisor_Toolkit_Standalone_Node.zip`

1. Proceed to extract the compressed file to obtain the ESC Installer.

   ```bash
   unzip Edge_Microvisor_Toolkit_Standalone_Node.zip
   ```

1. Navigate to the extracted folder & modify the permissions of the
‘edgesoftware’ file to make it executable.

   ```bash
   chmod +x edgesoftware
   ```

1. Execute the Edge Software Catalog Installer to begin the installation process by using the
following command:

   ```bash
   sudo ./edgesoftware install
   ```
Adhere to the console guidelines to set up the USB bootable flash drive.

## Step 4: Install Edge Microvisor Toolkit and Cluster setup

1. Once the script has finished successfully, eject the USB device
1. Ensure that USB boot is enabled in BIOS on the target device. Check that the USB boot option is highest in boot order priority to ensure that it will be booting from USB and not attempt network boot or boot from the system's NVMe/SSD.
1. The Runtime OS will install the Edge Microvisor Toolkit and continues to create the kubernetes cluster
1. User shall connect to the Standalone node using credential or ssh keys.
1. Copy the required kubeconfig file Development system for Cluster management and application deployment.

## Step 5: Application Deployment
1. User can install the application using helm charts 
1. Refer to Get started guide for more details to deploy the application
