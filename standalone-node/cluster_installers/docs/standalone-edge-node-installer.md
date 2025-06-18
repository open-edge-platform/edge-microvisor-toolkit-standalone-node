<!--
SPDX-FileCopyrightText: (C) 2025 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Standalone Edge Node installer

## Preparing installer

1. Run the `download_charts_and_images.sh` script - it will:

    > **Note:** Script uses podman to download artifacts

    - Download RKE2 artifacts to current directory
    - Download all base extension charts into `./charts` directory and convert
      them to base64 encoding
    - Download all the images used by the extensions into `./images` directory
      and package them as `tar.zst`
    - Download K8s dashboard as an extensions (manifest + images)
    - Create helmchart addon definitions based on extension templates and
      base64 encoded helmcharts downloaded

    ```shell
    ./download_charts_and_images.sh
    ```

    > **Note:** Base64 outputs in `./charts` directory need to be used as input into
      the helmchart definitions into each extension. Correctly prepared manifests are
      already committed with the base64 encoded charts included.

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
   There are two options to build a package

    - Build full package with RKE2 images/binaries, installation script, base
      extensions chart and container images, K8s dashboard manifest and images.

    ```shell
    ./build_package.sh
    ```

    - Build package with RKE2 images/binaries, installation script, base extensions
      chart and K8s dashboard manifest. The container image are not archived as part
      of this package and they are expected to be pulled from internet during RKE2
      cluster bootstrap on the Edge Node.

    ```shell
    ./build_package.sh --no-ext-image
    ```

## Installing

To install Microvisor on the Standalone Node

1. Copy the package to a writable directory ie. `/tmp/rke2-artifacts`

    ```shell
    mkdir /tmp/rke2-artifacts
    cp sen-rke2-package.tar.gz /tmp/rke2-artifacts
    ```

2. Unpack the package

    ```shell
    cd /tmp/rke2-artifacts
    tar xf sen-rke2-package.tar.gz
    ```

3. Run installer

    - By default installer is expecting the packages in `/tmp/rke2-artifacts`

        ```shell
        ./sen-rke2-installer.sh
        ```

    - If different path is selected to download the artifacts to then the installer
      can be pointed to it by providing the path as an argument

        ```shell
        ./sen-rke2-installer.sh /some/other/directory
        ```

4. Wait for install to finish and then all pods to come up running

    ```shell
    sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get pods -A
    ```

## Uninstalling

To uninstall RKE2 with SEN

```shell
cd /tmp/rke2-artifacts
./sen-uninstall-rke2.sh
```

## Next steps

For next steps see [Using SEN from development machine](./development-machine-usage.md)
