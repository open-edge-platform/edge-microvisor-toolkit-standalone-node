# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

#!/bin/bash

RKE_INSTALLER_PATH=/"${1:-/tmp/rke2-artifacts}"
# for basic testing on a coder setup
if grep -q "Ubuntu" /etc/os-release; then
	export IS_UBUNTU=true
else
	export IS_UBUNTU=false
fi

#Configure RKE2
sudo mkdir -p /etc/rancher/rke2
sudo bash -c 'cat << EOF >  /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
cluster-cidr: "10.42.0.0/16"
cni:
  - multus
  - calico
disable:
  - rke2-canal
  - rke2-ingress-nginx
disable-kube-proxy: false
etcd-arg:
  - --cipher-suites=[TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_CHACHA20_POLY1305_SHA256]
etcd-expose-metrics: false
kube-apiserver-arg:
  - "feature-gates=PortForwardWebsockets=true"
  - "tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
service-cidr: "10.43.0.0/16"
kubelet-arg:
  - "topology-manager-policy=best-effort"
  - "cpu-manager-policy=static"
  - "reserved-cpus=1"
  - "max-pods=250"
  - "tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
protect-kernel-defaults: true
EOF'


# Set up coredns
sudo mkdir -p /var/lib/rancher/rke2/server/manifests/
sudo bash -c 'cat << EOF >  /var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    global:
      clusterCIDR: 10.42.0.0/16
      clusterCIDRv4: 10.42.0.0/16
      clusterDNS: 10.43.0.10
      rke2DataDir: /var/lib/rancher/rke2
      serviceCIDR: 10.43.0.0/16
    resources:
      limits:
        cpu: "250m"
      requests:
        cpu: "250m"
EOF'

# Set up mirrors
sudo bash -c 'cat << EOF >  /etc/rancher/rke2/registries.yaml
mirrors: 
 docker.io: 
   endpoint: ["https://localhost.internal:9443"]
   
 rs-proxy.rs-proxy.svc.cluster.local:8443: 
   endpoint: ["https://localhost.internal:9443"]
EOF'

mkdir -p /var/lib/rancher/rke2/server/manifests/
sudo bash -c 'cat << EOF >  /var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-calico
  namespace: kube-system
spec:
  valuesContent: |-
    felixConfiguration:
      wireguardEnabled: true
    installation:
      calicoNetwork:
        nodeAddressAutodetectionV4:
          kubernetes: "NodeInternalIP"
EOF'

# Install RKE2
sudo INSTALL_RKE2_ARTIFACT_PATH=${RKE_INSTALLER_PATH} sh install.sh

# Copy the cni tarballs
sudo cp rke2-images-multus.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images
sudo cp rke2-images-calico.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images

# Copy extension images - if the images are part of the package - otherwise get pullled from internet
if [ -d ./images ]; then
	sudo cp ./images/* /var/lib/rancher/rke2/agent/images
fi

# Copy extensions (HelmChart definitions - charts encoded in yaml)
sudo cp ./extensions/* /var/lib/rancher/rke2/server/manifests

if [ "$IS_UBUNTU" = true ]; then
  sudo sed -i '14i EnvironmentFile=-/etc/environment' /usr/local/lib/systemd/system/rke2-server.service
else
  sudo sed -i '14i EnvironmentFile=-/etc/environment' /etc/systemd/system/rke2-server.service
fi

# Start RKE2
sudo systemctl enable --now rke2-server.service

until sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl version &>/dev/null; do echo "Waiting for Kubernetes API..."; sleep 5; done;

# Label node as a worker
hostname=$(hostname)
sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl label node $hostname node-role.kubernetes.io/worker=true

## This is a workaround for missing namespaces preventing netowork-policy chart to complete
sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl create ns cattle-system
sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl create ns local
