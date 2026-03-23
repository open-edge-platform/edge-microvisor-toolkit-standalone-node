#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Define a function to run kubectl with proper KUBECONFIG
k3s_kubectl() {
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/bin/k3s kubectl "$@"
}

k3s_helm() {
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm "$@"
}

echo "Starting app-deploy.sh script via cloud-init."

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ubuntu|emtd> <windows>"
    echo "First argument: ubuntu or emtd"
    echo "Second argument: windows"
    exit 1
fi

VM1="$1"
VM2="$2"

# Wait for k3s service to be active
echo "Checking k3s.service status..."
while [ "$(systemctl is-active k3s.service)" != "active" ]; do
    echo "Waiting for k3s.service to be active..."; sleep 5;
done
echo "k3s.service is running."

echo "Waiting for all pods in required namespaces to be Running and Ready..."
TIMEOUT=3000
# Set the interval between checks in seconds
INTERVAL=10
# Get the current time
START_TIME=$(date +%s)
while true; do
  # Get the current time
  CURRENT_TIME=$(date +%s)

  # Calculate the elapsed time
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

  # Check if the timeout has been reached
  if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
    echo "ERROR: Pods did not become ready within the timeout."
    exit 1
  fi

  # Check the status of all pods in all namespaces
  NOT_READY_PODS=$(k3s_kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o custom-columns=NAME:.metadata.name --no-headers)

  # If there are no not-ready pods, exit the loop
  if [ -z "$NOT_READY_PODS" ]; then
    echo "All pods are ready."
    break
  fi

  # Print the names of not-ready pods
  echo "Waiting for pods to become ready..."
  echo "$NOT_READY_PODS"

  # Wait for the specified interval before checking again
  sleep $INTERVAL
done
echo "All Kubernetes pods are ready."

# Wait for virt-api service to be available
echo "Waiting for virt-api service to be available in kubevirt namespace..."
while ! k3s_kubectl get svc virt-api -n kubevirt &>/dev/null; do
    echo "Waiting for virt-api service..."; sleep 5;
done
echo "virt-api service is available."

# Check if the namespace 'user-apps' exists, and create it if not
echo "Checking for 'user-apps' namespace..."
if ! k3s_kubectl get ns user-apps &>/dev/null; then
    k3s_kubectl create ns user-apps
    echo "Namespace 'user-apps' created."
else
    echo "Namespace 'user-apps' already exists."
fi

echo "Changing directory to /opt/user-apps/helm_charts/sidecar"

cd /opt/user-apps/helm_charts/sidecar || { echo "ERROR: Failed to change directory to sidecar charts."; exit 1; }

# Apply configmap for VM1 (ubuntu or emtd)
if [ "$VM1" = "ubuntu" ]; then
    echo "Checking for 'sidecar-ub22-dp1' configmap..."
    if ! k3s_kubectl get cm sidecar-ub22-dp1 -n user-apps &>/dev/null; then
        echo "Applying 'ub22_dp1.yaml'..."
        k3s_kubectl apply -f ub22_dp1.yaml
        echo "Applied 'ub22_dp1.yaml'."
    else
        echo "'sidecar-ub22-dp1' already exists, skipping 'ub22_dp1.yaml'."
    fi
elif [ "$VM1" = "emtd" ]; then
    echo "Checking for 'sidecar-emtd-dp1' configmap..."
    if ! k3s_kubectl get cm sidecar-emtd-dp1 -n user-apps &>/dev/null; then
        echo "Applying 'emtd_dp1.yaml'..."
        k3s_kubectl apply -f emtd_dp1.yaml
        echo "Applied 'emtd_dp1.yaml'."
    else
        echo "'sidecar-emtd-dp1' already exists, skipping 'emtd_dp1.yaml'."
    fi
else
    echo "ERROR: First argument must be 'ubuntu' or 'emtd'."
    exit 1
fi

# Apply configmap for VM2 (windows)
if [ "$VM2" = "windows" ]; then
    echo "Checking for 'sidecar-win11-dp1' configmap..."
    if ! k3s_kubectl get cm sidecar-win11-dp1 -n user-apps &>/dev/null; then
        echo "Applying 'win11_dp1.yaml'..."
        k3s_kubectl apply -f win11_dp1.yaml
        echo "Applied 'win11_dp1.yaml'."
    else
        echo "'sidecar-win11-dp1' already exists, skipping 'win11_dp1.yaml'."
    fi
else
    echo "ERROR: Second argument must be 'windows'."
    exit 1
fi

echo "Running usb-detect-assign.sh..."
bash /opt/user-apps/scripts/management/usb-detect-assign.sh -f /opt/user-apps/helm_charts/sidecar/ || { echo "WARNING: usb-detect-assign.sh failed."; }

# Wait for virtio endpoint to be ready for access
sleep 30

# Adding workaround: Uninstall of Windows and Ubuntu VMs to avoid the SRIOV-VFs not ready before the VM pods starts.
echo "Helm uninstall 'ub22vm'"
k3s_helm uninstall ub22vm -n user-apps || { echo "ERROR: Failed to uninstall helm-ub22_dp1 charts."; }
echo "Helm uninstall 'win11vm'"
k3s_helm uninstall win11vm -n user-apps || { echo "ERROR: Failed to uninstall helm-win11_dp1 charts."; }

# Adding workaround: Sidecar changes are not applied when the USB devices port numbers are changed after reboot
cd /opt/user-apps/helm_charts/sidecar || { echo "ERROR: Failed to change directory to sidecar charts."; exit 1; }
echo "Applying 'win11_dp1.yaml'..."
k3s_kubectl apply -f win11_dp1.yaml
echo "Applying 'ub22_dp1.yaml'..."
k3s_kubectl apply -f ub22_dp1.yaml

sleep 10

# Deploy Helm chart for VM1
if [ "$VM1" = "ubuntu" ]; then
    echo "Checking if Helm release 'ub22vm' is already deployed..."
    if ! k3s_helm list -A | grep -q 'ub22vm'; then
        echo "Helm release 'ub22vm' not found. Attempting installation."
        cd /opt/user-apps/helm_charts/helm-ub22_dp1 || { echo "ERROR: Failed to change directory to helm-ub22_dp1 charts."; exit 1; }
        if k3s_helm install ub22vm -n user-apps .; then
            echo "Helm installation succeeded for ub22vm."
        else
            echo "Helm installation failed for ub22vm."
            exit 1
        fi
    else
        echo "Helm release 'ub22vm' already deployed, skipping installation."
    fi
elif [ "$VM1" = "emtd" ]; then
    echo "Checking if Helm release 'emtdvm' is already deployed..."
    if ! k3s_helm list -A | grep -q 'emtdvm'; then
        echo "Helm release 'emtdvm' not found. Attempting installation."
        cd /opt/user-apps/helm_charts/helm-emtd_dp1 || { echo "ERROR: Failed to change directory to helm-emtd_dp1 charts."; exit 1; }
        if k3s_helm install emtdvm -n user-apps .; then
            echo "Helm installation succeeded for emtdvm."
        else
            echo "Helm installation failed for emtdvm."
            exit 1
        fi
    else
        echo "Helm release 'emtdvm' already deployed, skipping installation."
    fi
fi

# Deploy Helm chart for VM2 (windows)
echo "Checking if Helm release 'win11vm' is already deployed..."
if ! k3s_helm list -A | grep -q 'win11vm'; then
    echo "Helm release 'win11vm' not found. Attempting installation."
    cd /opt/user-apps/helm_charts/helm-win11_dp1 || { echo "ERROR: Failed to change directory to helm-win11_dp1 charts."; exit 1; }
    if k3s_helm install win11vm -n user-apps .; then
        echo "Helm installation succeeded for win11vm."
    else
        echo "Helm installation failed for win11vm."
        exit 1
    fi
else
    echo "Helm release 'win11vm' already deployed, skipping installation."
fi

echo "app-deploy.sh script finished."
