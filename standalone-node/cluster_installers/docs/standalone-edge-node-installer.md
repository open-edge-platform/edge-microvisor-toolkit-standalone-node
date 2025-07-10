# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Standalone Edge Node installer

## Build
To build the install script package simply run

```shell
./build_package.sh
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
- the installer assumes that all necessary images and manifests already exist on the filesystem
- If different path is selected to download the artifacts to then the installer can be pointed to it by providing the path as an argument
- The installer will set a CIDR of ``10.42.0.0/16``. This may need to be set in your NO_PROXY and no_proxy environemnt variables before install.

```shell
./sen-k3s-installer.sh /some/other/directory
```

1. Wait for install to finish and then all pods to come up running

```shell
sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml /usr/local/bin/k3s kubectl get pods -A
```
TODO: move to /usr/local/bin/ when binaries are available.

The k3s binary provides a wrapper of kubectl through the `k3s kubectl` command.

## Next steps

For next steps see [Using SEN from development machine](./development-machine-usage.md)
