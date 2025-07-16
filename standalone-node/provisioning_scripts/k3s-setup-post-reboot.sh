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
       while sudo -E KUBECONFIG=/etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/bin/k3s kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | grep -q .; do
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

banner="
===================================================================
Edge Microvisor Toolkit - cluster bringup complete
Logs located at:
        /var/log/cluster-init.log

For k3s logs run:
        sudo journalctl -fu k3s

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
