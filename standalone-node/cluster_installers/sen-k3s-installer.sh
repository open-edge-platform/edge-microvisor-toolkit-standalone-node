#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=all

K3S_BIN_PATH="${1:-/usr/bin}"

#Remove log file
sudo rm -rf /var/log/cluster-init.log

#Configure k3s
echo "$(date): Configuring k3s 1/12" | sudo tee /var/log/cluster-init.log | sudo tee /dev/tty0
sudo mkdir -p /etc/rancher/k3s
sudo bash -c 'cat << EOF >  /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
cluster-init: true
cluster-cidr: "10.42.0.0/16"
cluster-dns: "10.43.0.10"
data-dir : /var/lib/rancher/k3s
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
  - "volume-plugin-dir=/var/lib/kubelet/volumeplugins"
protect-kernel-defaults: true
disable:
  - traefik
  - servicelb
EOF'


sudo mkdir -p /var/lib/rancher/k3s/server/manifests/
sudo mkdir -p $K3S_BIN_PATH

# Set up mirrors
sudo bash -c 'cat << EOF >  /etc/rancher/k3s/registries.yaml
mirrors: 
 docker.io: 
   endpoint: ["https://localhost.internal:9443"]
   
 rs-proxy.rs-proxy.svc.cluster.local:8443: 
   endpoint: ["https://localhost.internal:9443"]
EOF'

echo "$(date): Installing k3s 2/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
sudo INSTALL_K3S_BIN_DIR=$K3S_BIN_PATH INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_SYMLINK='skip' INSTALL_K3S_BIN_DIR_READ_ONLY=true sh /opt/install.sh

sudo sed -i '14i EnvironmentFile=-/etc/environment' /etc/systemd/system/k3s.service


# Start k3s
echo "$(date): Starting k3s 3/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
sudo systemctl enable --now k3s

echo "$(date): Waiting for k3s to start 4/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
until sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml $K3S_BIN_PATH/k3s kubectl version &>/dev/null; do echo "Waiting for Kubernetes API..."; sleep 5; done;
echo "$(date): k3s started 5/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
# Label node as a worker
hostname=$(hostname | tr '[:upper:]' '[:lower:]')
sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml $K3S_BIN_PATH/k3s kubectl label node $hostname node-role.kubernetes.io/worker=true

# Wait for the deployment to complete

## First wait for all namespaces to be created
namespaces=(
	"kube-node-lease"
	"kube-public"
	"kube-system")
echo "$(date): Waiting for namespaces to be created 6/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
while true; do
  all_exist=true
  for ns in "${namespaces[@]}"; do
    sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml $K3S_BIN_PATH/k3s kubectl get namespace "$ns" &> /dev/null || all_exist=false
  done
  $all_exist && break
  echo "Waiting for namespaces to be created..."
  sleep 5
done

echo "$(date): Namespaces created 7/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

echo "$(date): Permissive network policies created 8/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

## Wait for all pods to deploy
echo "$(date): Waiting for all extensions to deploy 9/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
echo "Waiting for all extensions to complete the deployment..."
while sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml $K3S_BIN_PATH/k3s kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | grep -q .; do
  echo "Some pods are still not ready. Checking again in 5 seconds..."
  sleep 5
done
echo "$(date): All extensions deployed 10/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0

echo "$(date): Configuring environment 11/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
## Add k3s binary to path
sed 's|PATH="|PATH="'$K3S_BIN_PATH':|' /etc/environment > /tmp/environment.tmp && sudo cp /tmp/environment.tmp /etc/environment && rm /tmp/environment.tmp
source /etc/environment
export KUBECONFIG

# All pods deployed - write to log
echo "$(date): The cluster installation is complete 12/12" | sudo tee -a /var/log/cluster-init.log | sudo tee /dev/tty0
echo "$(date): The cluster installation is complete!"

# Print banner
IP=$(sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml $K3S_BIN_PATH/k3s kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
IPCHECK="/var/lib/rancher/ip.log"

if [ ! -f "$IPCHECK" ]; then
    echo "$IP" | sudo tee "$IPCHECK"
fi

# Add k3s installation flag, so that on next reboot it will not start again from begining.

K3S_STATUS="/var/lib/rancher/k3s_status"

if [ ! -f "$K3S_STATUS" ]; then
    echo "success" | sudo tee "$K3S_STATUS"
fi

# Print banner

banner="
===================================================================
Edge Microvisor Toolkit - cluster installation complete
Logs located at:
	/var/log/cluster-init.log

For k3s logs run:
	sudo journalctl -fu k3s

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
	/etc/rancher/k3s/k3s.yaml
===================================================================
"

# Print the banner
echo "$banner" | sudo tee /dev/tty0
