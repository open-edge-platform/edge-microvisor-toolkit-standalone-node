# Get Started Guide

The installation flow for **Intel® Edge Microvisor Toolkit Standalone Node – Edge Software Hub** is primarily intended for public/external users.The primary objective of the Intel® Edge Microvisor Toolkit Standalone Node product is to enable customers to deploy and evaluate Intel Architecure based platfroms for Edge and Edge AI applications.The Edge Microvisor Toolkit Standalone Node Software is installed through **ESC QA (Edge Software Hub)**. Users log in to ESC, select the released package, and download the installer package. 

The user extracts and copies the EdgeNode install package to the development systems and executes the installer to support standalone USB-based edge node installation of the Edge Microvisor Toolkit. The installation process includes setting up Kubernetes, all necessary Kubernetes extensions (device plugins, scheduler extensions, CNIs, CSIs, etc.). Ultimately, the standalone EdgeNode based on the Edge Microvisor Toolkit supports customers in deploying workloads in an independent standalone cluster. Once the evaluation is complete, customers can onboard this EdgeNode to the backend as part of the product deployment.

> **Note:** Software updates to the Foundation Edge Nodes are done manually by downloading an updated version of the Intel Edge Microvisor Toolkit Standalone Node package. There is no automatic update process for Edge Nodes in this scenario.

---

## Installation Process for Intel® Edge Microvisor Toolkit Standalone Node

![Installation flow](_images/installation_flow.png)  
*<center>Figure 1: Flow for Intel® Edge Microvisor Toolkit Standalone Node</center>*

---

## Step 1: Prerequisites & System Setup

Before starting the Edge Node deployment, ensure the following:

- System is bootable to a fresh **Ubuntu 22.04**.
- Internet connectivity is available on the node.
- The target node(s) hostname must be in lowercase, numerals, and hyphens (`-`).  
  - **Example:** `wrk-8` is acceptable; `wrk_8`, `WRK8`, and `Wrk^8` are not.
- Required proxy settings must be added to the `/etc/environment` file.
- Access to the **Edge Software Hub portal** is available.

---

## Step 2: Download the ESC Package

1. Select **Configure & Download** to download the Intel® Edge Microvisor Toolkit Standalone Node package.  
   <a href="https://edge-services-catalog-prod-qa.apps1-bg-int.icloud.intel.com/package/edge_microvisor_toolkit_standalone_node" style="display: inline-block; padding: 10px 20px; font-size: 16px; font-weight: bold; color: white; background-color: #007bff; text-align: center; text-decoration: none; border-radius: 5px; border: none;">Configure & Download</a>

---

## Step 3: Configure

The ESC package will be downloaded to your local system in a zip format labeled as `Edge_Microvisor_Toolkit_Standalone_Node.zip`.

1. Copy the ESC package to an Edge Node running **Ubuntu 22.04**:
   ```bash
   mkdir Test
   chmod 750 Test
   ```
   ![Copy Package](_images/copy_pkg.png)  
   *<center>Figure 6: Copy ESC Package to Target System</center>*

2. Extract the compressed file to obtain the ESC Installer:
   ```bash
   unzip Edge_Microvisor_Toolkit_Standalone_Node.zip
   ```
   ![Unzip Package](_images/unzip.png)  
   *<center>Figure 7: Unzip the ESC Package</center>*

3. Navigate to the extracted folder and modify the permissions of the `edgesoftware` file to make it executable:
   ```bash
   chmod +x edgesoftware
   ```
   ![Change Permission](_images/chmod.png)  
   *<center>Figure 8: Change Installer Permission</center>*

---

## Step 4: Deploy

Execute the ESC Installer to begin the installation process:
```bash
sudo ./edgesoftware install
```
![Folder Structure](_images/ESC-install-dir.png)

### 4.1 User Inputs Required for Installation

<details>
<summary><b>User Inputs</b> for <b>Edge Microvisor Toolkit Standalone Node Package</b></summary>

#### Parameters:

| **Prompt**         | **User Input**                                   |
|---------------------|-------------------------------------------------|
| HTTP Proxy          | Enter the HTTP proxy (leave blank for none)     |
| HTTPS Proxy         | Enter the HTTPS proxy (leave blank for none)    |
| No Proxy            | Enter the NO proxy (leave blank for none)       |
| SSH Key             | Enter the SSH key                               |
| User Name           | Enter the user name                             |
| Password            | Enter the password                              |
| Disk                | Enter the disk                                  |

</details>

---

## Step 5: Gain Access to the Edge Node from a Development Machine

A development machine can be used to interact with the Edge Node. Ensure the development machine and Edge Node are on the same network with no communication obstacles.

> **Note:** The same functionality can be achieved in a Linux environment by executing Linux-equivalent commands.

---

## Step 6: Set Up Tools on Development Machine

Install and configure `kubectl` and `helm` tools on the development machine.

> **Note:** Replace the user and disk used in the development machine throughout the commands provided in this tutorial. Replace `<EN IP>` with the actual Edge Node IP address.

1. Install `kubectl`:
   ```powershell
   PS C:\Users\user> winget install -e --id Kubernetes.kubectl
   PS C:\Users\user> mkdir .kube
   PS C:\Users\user> New-Item config -type file
   ```

2. Copy the kubeconfig file from the Edge Node:
   ```powershell
   PS C:\Users\user> scp user@<EN IP>:/etc/rancher/rke2/rke2.yaml C:\Users\user\.kube\config
   ```

3. Update the Edge Node IP in the kubeconfig file:
   ```powershell
   PS C:\Users\user> (Get-Content -Path "C:\Users\user\.kube\config") -replace "127\.0\.0\.1", "<EN IP>" | Set-Content -Path "C:\Users\user\.kube\config"
   ```

4. Test the connection:
   ```powershell
   PS C:\Users\user> kubectl get pods -A
   ```

5. Install `helm`:
   ```powershell
   PS C:\Users\user> winget install Helm.Helm
   ```

---

## Step 7: Set Up Kubernetes Dashboard Access

1. View the Kubernetes dashboard pods:
   ```powershell
   PS C:\Users\user> kubectl get pods -n kubernetes-dashboard
   ```

2. Enable kube proxy:
   ```powershell
   PS C:\Users\user> kubectl proxy
   ```

3. Generate an access token:
   ```powershell
   PS C:\Users\user> kubectl -n kubernetes-dashboard create token admin-user
   ```

4. Access the dashboard in a browser:  
   `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login`

---

## Step 8: Install Sample Application

Install a WordPress application as a test application using `helm`.

1. Add the `bitnami` repository:
   ```powershell
   PS C:\Users\user> helm repo add bitnami https://charts.bitnami.com/bitnami
   ```

2. Create a values override file `values-wp.yaml` and install WordPress:
   ```powershell
   PS C:\Users\user> helm install my-wordpress bitnami/wordpress --namespace wordpress --create-namespace -f .\values-wp.yaml --version 19.4.3
   ```

---

## Step 9: Accessing Grafana

1. Retrieve Grafana credentials:
   ```powershell
   PS C:\Users\user> kubectl get secret grafana -n observability -o jsonpath="{.data.admin-user}" | % { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
   ```

2. Access Grafana in a browser:  
   `http://<EN IP>:32000`

---

## Step 12: Uninstall Edge Microvisor Toolkit Standalone Node Package

To uninstall, navigate to the directory where the ESC installer is extracted and run:
```bash
./edgesoftware uninstall
```

---

## Troubleshooting

- Ensure the Edge Node retains the same IP address across reboots, as the Kubernetes cluster depends on the initially configured IP address. If the IP changes, the cluster may not function properly.
- Verify network connectivity and proxy settings if issues arise.

