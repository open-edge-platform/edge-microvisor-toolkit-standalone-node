# Analysis: K3s Container images and CNI support in EMT

**Author(s):** Krishna

**Last Updated:** 2025-12-07

## Abstract

This document provides a technical analysis of running upstream K3s container images and CNI (Container Network Interface)
plugins on Edge Microvisor Toolkit (EMT). It explores strategies to streamline the integration of complete K3s artifacts
into EMT, focusing on minimizing the redistribution of upstream binaries and optimizing the overall footprint. The goal is
to enable robust Kubernetes and networking capabilities on EMT while maintaining efficiency, security, and
compliance with upstream licensing and distribution requirements.

## Data points on EMT non-Real Time image

Kubernetes pods

```shell
user@EdgeMicrovisorToolkit [ ~ ]$ k get po -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   coredns-697968c856-wjgcr                  1/1     Running   0          24s
kube-system   local-path-provisioner-774c6665dc-vr7fn   1/1     Running   0          24s
kube-system   metrics-server-6f4c6675d5-p4dm7           0/1     Running   0          24s
```

Container images corresponding to the pods

```shell
user@EdgeMicrovisorToolkit [ ~ ]$ k get pods -A -o custom-columns="POD:.metadata.name,CONTAINERS:.spec.containers[*].name"
POD                                       CONTAINERS
coredns-697968c856-wjgcr                  coredns
local-path-provisioner-774c6665dc-vr7fn   local-path-provisioner
metrics-server-6f4c6675d5-p4dm7           metrics-server
```

```shell
user@EdgeMicrovisorToolkit [ /opt/k3s-airgap ]$ k get pods -A -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n' | sort | uniq
docker.io/rancher/local-path-provisioner:v0.0.31
docker.io/rancher/mirrored-coredns-coredns:1.12.1
docker.io/rancher/mirrored-metrics-server:v0.7.2
rancher/local-path-provisioner:v0.0.31
rancher/mirrored-coredns-coredns:1.12.1
rancher/mirrored-metrics-server:v0.7.2
```

Container images part of the k3s airgap image

below is the list of container images that are part of the k3s airgap image `k3s-airgap-images-amd64.tar.zst`:

```shell
user@EdgeMicrovisorToolkit [ /opt/k3s-airgap ]$ cat repositories | jq
{
  "rancher/klipper-helm": {
    "v0.9.5-build20250306": "4e06f098ec396faaba772ed3c857d728606175c333fd04e789a7e7a8d8534295"
  },
  "rancher/klipper-lb": {
    "v0.4.13": "aa0e9394db0863bbe18e5a30a7d72fabd0f77767a863b91d28350fb3a2980f85"
  },
  "rancher/local-path-provisioner": {
    "v0.0.31": "e8ac39c5d130730c5aa00302a063df3b48d9dae6332836e260c249a2fff758b8"
  },
  "rancher/mirrored-coredns-coredns": {
    "1.12.1": "d3678837e388fc6ab20e7345571428bc16361023c0bd5d9d2b1713c7c23aa0f7"
  },
  "rancher/mirrored-library-busybox": {
    "1.36.1": "5c0f3fead72708bd3c841cf9b41c2b772569c4404012fbfca9f3a0cd37b85c58"
  },
  "rancher/mirrored-library-traefik": {
    "3.3.6": "f27a72f9b2fa02ac7d0b7775454ce615a5dad16db9bde97a1704e9d3976a2dd1"
  },
  "rancher/mirrored-metrics-server": {
    "v0.7.2": "6b27faa06dc04b39a0b117c78f9e426cb3901ebd07dcf56c4766d805d391ddc8"
  },
  "rancher/mirrored-pause": {
    "3.6": "83e36d6cc6a9c77e200396b5f8bffe3c1a45ebe2093f9301a39074db5fc86cd2"
  }
}
```

The table below summarizes the container images that are part of the k3s airgap image and their corresponding tags.

#### K3s Airgap Image Contents vs Running Pods

| Image Name                         | Tag                  | Description / Use                                                  | In Use (Running Pod)     |
| ----------------------------------- | -------------------- | ------------------------------------------------------------------ | ------------------------ |
| `rancher/klipper-helm`              | v0.9.5-build20250306 | K3s internal Helm controller for deploying Helm charts             | ❌ Not running           |
| `rancher/klipper-lb`                | v0.4.13              | Lightweight LoadBalancer implementation used by K3s on bare metal  | ❌ Not running           |
| `rancher/local-path-provisioner`    | v0.0.31              | Dynamic local PV provisioning (for storage)                        | ✅ Running               |
| `rancher/mirrored-coredns-coredns`  | 1.12.1               | CoreDNS service for DNS in the cluster                             | ✅ Running               |
| `rancher/mirrored-library-busybox`  | 1.36.1               | Minimal base image often used in testing/debug Pods                | ❌ Not running           |
| `rancher/mirrored-library-traefik`  | 3.3.6                | Default ingress controller (used only if enabled in K3s)           | ❌ Not running           |
| `rancher/mirrored-metrics-server`   | v0.7.2               | Metrics server for resource usage metrics (used by HPA, etc.)      | ✅ Running               |
| `rancher/mirrored-pause`            | 3.6                  | Pause container for pod sandboxing (used internally by Kubernetes) | ✅ Implicitly running    |

#### K3s Airgap continer images licenses

| Image Name                         | Tag                  | License      | License Link                                                                                  |
|-------------------------------------|----------------------|--------------|----------------------------------------------------------------------------------------------|
| rancher/klipper-helm                | v0.9.5-build20250306 | Apache-2.0   | <https://github.com/k3s-io/klipper-helm/blob/master/LICENSE>                                   |
| rancher/klipper-lb                  | v0.4.13              | Apache-2.0   | <https://github.com/k3s-io/klipper-lb/blob/master/LICENSE>                                     |
| rancher/local-path-provisioner      | v0.0.31              | Apache-2.0   | <https://github.com/rancher/local-path-provisioner/blob/master/LICENSE>                        |
| rancher/mirrored-coredns-coredns    | 1.12.1               | Apache-2.0   | <https://github.com/coredns/coredns/blob/master/LICENSE>                                       |
| rancher/mirrored-library-busybox    | 1.36.1               | GPL-2.0      | <https://github.com/mirror/busybox/blob/master/LICENSE>                                        |
| rancher/mirrored-library-traefik    | 3.3.6                | MIT          | <https://github.com/traefik/traefik/blob/master/LICENSE.md>                                    |
| rancher/mirrored-metrics-server     | v0.7.2               | Apache-2.0   | <https://github.com/kubernetes-sigs/metrics-server/blob/master/LICENSE>                        |
| rancher/mirrored-pause              | 3.6

Conclusion: The K3s airgap image contains several container images, but only a subset is actively used in the current EMT deployment. The images that are not running can be considered for removal to reduce the overall footprint.
