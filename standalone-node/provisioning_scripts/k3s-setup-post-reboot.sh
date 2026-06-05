#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=all

# Ensure k3s config.yaml is always present before k3s is restarted.
# /etc overlay is persistent (upper on ext4), but config may be missing
# if the system was provisioned without create_k3s_base_config in install-os.sh.
mkdir -p /etc/rancher/k3s
if [ ! -f /etc/rancher/k3s/config.yaml ]; then
    cat << 'EOF' > /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
cluster-cidr: "10.42.0.0/16"
cluster-dns: "10.43.0.10"
data-dir : /opt/rancher/k3s
disable-kube-proxy: false
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
EOF
    echo "k3s config.yaml was missing; written and restarting k3s" | sudo tee /dev/tty0
    sudo systemctl restart k3s
fi

IPCHECK="/opt/rancher/ip.log"
# Check if the IP address changes, if changes print the banner
host_prev_ip=$(cat "$IPCHECK")

# Get the system ip
while [ true ]
do
    pub_interface_name=$(route | grep '^default' | grep -o '[^ ]*$')
    if [ -z "$pub_interface_name" ]; then
        sleep 3
    else
        host_ip=$(ifconfig "${pub_interface_name}" | grep 'inet ' | awk '{print $2}')
	break
    fi
done
if [[ "$host_ip" != "$host_prev_ip" ]]; then
   echo "The Edge Node IP($host_ip) has changed since k3s install"
   banner="
================================================================================
OLD k3s cluster IP $host_prev_ip
NEW k3s cluster IP $host_ip
=================================================================================
"
   # Print the banner
   sleep 10
   echo "$banner" | sudo tee /dev/tty0

   while [ true ]
   do
      k3s_status=$(systemctl is-active k3s)
      if [[ "$k3s_status" == "active" ]]; then
          echo "Reconfiguring cluster..." | sudo tee /dev/tty0
          k3s kubectl delete node edgemicrovisortoolkit
          sudo systemctl restart k3s
          echo "Restarted k3s" | sudo tee /dev/tty0
	  break
      else
          echo "K3s service is still not active. Checking in 10 seconds..." | sudo tee /dev/tty0
          sleep 10
      fi
   done
   echo $host_ip > $IPCHECK
fi

while [ true ]
do
   k3s_status=$(systemctl is-active k3s)
   if [[ "$k3s_status" == "active" ]]; then

       echo "Waiting for all extensions to complete the deployment..." | sudo tee /dev/tty0
       while sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml /opt/rancher/k3s/bin/k3s kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | grep -q .; do
       echo "Some pods are still not ready. Checking again in 5 seconds..." | sudo tee /dev/tty0
       sleep 5
       done
       break
   else
       echo "Waiting for k3s services to running state,please wait checking again in few seconds" | sudo tee /dev/tty0
       sleep 30
   fi
done

# Print banner
IP="$host_ip"
banner="
===================================================================
Edge Microvisor Toolkit - cluster bringup complete
Logs located at:
        /var/log/cluster-init.log

For k3s logs run:
        sudo journalctl -fu k3s

IP address of the Node:
	$IP - Ensure IP address is persistent across the reboot!

To access and view the cluster's pods run:
        source /etc/environment
        source /home/<default-user>/.bashrc
        k get pods -A

KUBECONFIG available at:
        /etc/rancher/k3s/k3s.yaml
===================================================================
"
# Print the banner
echo "$banner" | sudo tee /dev/tty0
