#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=all

RKE_INSTALLER_PATH=/"${1:-/tmp/rke2-artifacts}"
# for basic testing on a coder setup
if grep -q "Ubuntu" /etc/os-release; then
	export IS_UBUNTU=true
else
	export IS_UBUNTU=false
fi

#Remove log file
sudo rm -rf /var/log/cluster-init.log

#Configure RKE2
echo "$(date): Configuring RKE2 1/13" | sudo tee /var/log/cluster-init.log | sudo tee /dev/tty0
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
echo "$(date): Installing RKE2 2/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
sudo INSTALL_RKE2_ARTIFACT_PATH="${RKE_INSTALLER_PATH}" sh install.sh

# Copy the cni tarballs
echo "$(date): Copying images and extensions 3/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
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
echo "$(date): Starting RKE2 4/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
sudo systemctl enable --now rke2-server.service

echo "$(date): Waiting for RKE2 to start 5/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
until sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl version &>/dev/null; do echo "Waiting for Kubernetes API..."; sleep 5; done;
echo "$(date): RKE2 started 6/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
# Label node as a worker
hostname=$(hostname | tr '[:upper:]' '[:lower:]')
sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl label node "$hostname" node-role.kubernetes.io/worker=true

# Wait for the deployment to complete

## First wait for all namespaces to be created
namespaces=("calico-system"
	"cert-manager"
	"gatekeeper-system"
	"kube-node-lease"
	"kube-public"
	"kube-system"
	"kubernetes-dashboard"
	"nfd"
	"observability"
	"openebs"
	"tigera-operator")
echo "$(date): Waiting for namespaces to be created 7/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
while true; do
  all_exist=true
  for ns in "${namespaces[@]}"; do
    sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get namespace "$ns" &> /dev/null || all_exist=false
  done
  $all_exist && break
  echo "Waiting for namespaces to be created..."
  sleep 5
done

echo "$(date): Namespaces created 8/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

## Wait for NetworkPolicies to get created

sudo bash -c 'KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kubesystem-egress
  namespace: kube-system
spec:
  egress:
  - {}
  podSelector: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kubesystem-ingress
  namespace: kube-system
spec:
  ingress:
  - {}
  podSelector: {}
  policyTypes:
  - Ingress
EOF'
echo "$(date): Permissive network policies created 9/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

## Wait for all pods to deploy
echo "$(date): Waiting for all extensions to deploy 10/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
echo "Waiting for all extensions to complete the deployment..."
while sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | grep -q .; do
  echo "Some pods are still not ready. Checking again in 5 seconds..."
  sleep 5
done
echo "$(date): All extensions deployed 11/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

echo "$(date): Configuring environment 12/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
## Add kubectl to path
sed 's|PATH="|PATH="/var/lib/rancher/rke2/bin:|' /etc/environment > /tmp/environment.tmp && sudo cp /tmp/environment.tmp /etc/environment && rm /tmp/environment.tmp
source /etc/environment
export KUBECONFIG

# All pods deployed - write to log
echo "$(date): The cluster installation is complete 13/13" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
echo "$(date): The cluster installation is complete!"

IP=$(sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
IPCHECK="/var/lib/rancher/ip.log"

if [ ! -f "$IPCHECK" ]; then
    echo "$IP" | sudo tee "$IPCHECK"
fi

# Add rke2 installation flag, so that on next reboot it will not start again from begining.

RKE2_STATUS="/var/lib/rancher/rke2_status"

if [ ! -f "$RKE2_STATUS" ]; then
    echo "success" | sudo tee "$RKE2_STATUS"
fi

# Print banner

banner="
===================================================================
Edge Microvisor Toolkit - cluster installation complete
Logs located at:
	/var/log/cluster-init.log

For RKE2 logs run:
	sudo journalctl -fu rke2-server

IP address of the Node:
	$IP - Ensure IP address is persistent across the reboot!
        See: https://ranchermanager.docs.rancher.com/getting-started
	/installation-and-upgrade/installation-requirements#node-ip-
	addresses 

To access and view the cluster's pods run:
	source /etc/environment
	export KUBECONFIG
	kubectl get pods -A

KUBECONFIG available at:
	/etc/rancher/rke2/rke2.yaml
===================================================================
"

# Print the banner
echo "$banner" | sudo tee /dev/tty0
