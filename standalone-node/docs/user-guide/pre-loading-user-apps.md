# Pre-loading User Application artifacts as part of USB installer

Edge Microvisor Toolkit (EMT) Standalone Node enables users to quickly deploy a single-node
cluster based on lightweight Kubernetes. In scenarios such as OEM (Original Equipment Manufacturer)
use cases, users may need to pre-load applications onto the edge node before testing and shipping
it to its final installation site.This capability is especially useful for those who want their
applications to be available and ready for use immediately after installation.

To support these requirements, EMT Standalone Node allows users to include their application artifacts
within the USB installer.

After extracting the standalone node installer, users can find `user-apps` placeholder apps placed in the root of
the directory where installer is extracted. Users can place their application files like container
images, helm charts, VM images in the `user-apps` folder. The artifacts will be automatically copied
to persistent volume on the Edge node at `/opt/user-apps`. User can use the custom `cloud-init` section
available in the configuration file `config-file` to launch the application after the kubernetes cluster has come up.
User has flexibility to manage the artifacts and what they do using the artifacts and the custom
cloud-init configuration.

User should take 
