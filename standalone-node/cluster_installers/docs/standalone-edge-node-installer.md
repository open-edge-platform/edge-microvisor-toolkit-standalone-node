# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Standalone Edge Node installer

## Preparing installer

1. Run the `download_charts_and_images.sh` script - it will:

> Note: Script uses podman to download artifacts

- Download all extension charts into `./charts` directory and convert them to base64 encoding 
- Download all the images used by the extensions into `./images` directory and package them as `tar.zst`
- Create helmchart addon definitions based on extension templates and base64 encoded helmcharts downloaded

```shell
./download_charts_and_images.sh
```

> Note Base64 outputs in `./charts` directory need to be used as input into the helmchart definitions into each extension.
> Correctly prepared manifests are already committed with the base64 encoded charts included.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: <extensions>
  namespace: kube-system
spec:
  chartContent: <base64 encoded chart>
  targetNamespace: <extension namespace>
  createNamespace: true
  valuesContent: |-
    <values>
```

2. Build a tar package that includes the artifacts and installer/uninstall script

There is two options to build a package

- Build full package with installation script, extensions charts and container images.

```shell
./build_package.sh
```

- Build package with k3s images/binaries, installation script, extension charts and manifests. The container images are not archived as part of this package and they are expected to be pulled from internet during k3s cluster bootstrap on the Edge Node.
```shell
./build_package.sh --no-ext-image
```

## Installing

To install Microvisor on the Standalone Node

1. Copy the package to a writable directory ie. `/tmp/k3s-artifacts` 

```shell
mkdir /tmp/k3s-artifacts
cp sen-k3s-package.tar.gz /tmp/k3s-artifacts
```

2. Unpack the package

```shell
cd /tmp/k3s-artifacts
tar xf sen-k3s-package.tar.gz
```

3. Run installer

- By default installer is expecting the packages in `/tmp/k3s-artifacts`

```shell
./sen-k3s-installer.sh
```

- If different path is selected to download the artifacts to then the installer can be pointed to it by providing the path as an argument
- The installer will set a CIDR of ``10.42.0.0/16``. This may need to be set in your NO_PROXY and no_proxy environemnt variables before install.

```shell
./sen-k3s-installer.sh /some/other/directory
```

1. Wait for install to finish and then all pods to come up running

```shell
sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml /usr/bin/k3s kubectl get pods -A
```
TODO: move to /usr/local/bin/ when binaries are available.

The k3s binary provides a wrapper of kubectl through the `k3s kubectl` command.

## Next steps

For next steps see [Using SEN from development machine](./development-machine-usage.md)
