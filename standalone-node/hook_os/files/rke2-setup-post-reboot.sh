#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=all

IPCHECK="/var/lib/rancher/ip.log"
# Check if the IP address changes, if changes print the banner
host_prev_ip=$(cat "$IPCHECK")

# Get the system ip
while [ true ]
do
    pub_inerface_name=$(route | grep '^default' | grep -o '[^ ]*$')
    if [ -z "$pub_inerface_name" ]; then
        sleep 3
    else
        host_ip=$(ifconfig "${pub_inerface_name}" | grep 'inet ' | awk '{print $2}')
	break
    fi
done
if [[ "$host_ip" != "$host_prev_ip" ]]; then
   echo "IP changed"
   CHANGE_MSG="Warning: The Edge Node IP($host_ip) has changed since RKE2 install!"
   banner="
================================================================================
Edge Microvisor Toolkit - cluster bring up problem

****Looks the IP address of the system chnaged since RKE2 install*****

OLD RKE2 cluster IP $host_prev_ip
NEW RKE2 cluster IP $host_ip

IP address of the Node:
        $host_prev_ip - Ensure IP address is persistent across the reboot!
        See: https://ranchermanager.docs.rancher.com/getting-started
        /installation-and-upgrade/installation-requirements#node-ip-
        addresses $CHANGE_MSG

=================================================================================
"
   # Print the banner
   sleep 10
   echo "$banner" | sudo tee /dev/tty0
else
   CHANGE_MSG="IP address remained same after reboot." 
   while [ true ]
   do
      rke2_status=$(systemctl is-active rke2-server)
      if [[ "$rke2_status" == "active" ]]; then
	  
          echo "Waiting for all extensions to complete the deployment..." | sudo tee /dev/tty0
          while sudo -E KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | grep -q .; do
          echo "Some pods are still not ready. Checking again in 5 seconds..." | sudo tee /dev/tty0
          sleep 5
          done
	  break
      else
	  echo "Waiting for rke2 services to running state,please wait checking again in few seconds" | sudo tee /dev/tty0
	  sleep 30
      fi
   done

   # Print banner

    banner="
===================================================================
Edge Microvisor Toolkit - cluster bringup complete
Logs located at:
        /var/log/cluster-init.log

For RKE2 logs run:
        sudo journalctl -fu rke2-server

IP address of the Node:
        $IP - Ensure IP address is persistent across the reboot!
        See: https://ranchermanager.docs.rancher.com/getting-started
        /installation-and-upgrade/installation-requirements#node-ip-
        addresses $CHANGE_MSG

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
fi
