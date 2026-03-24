# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Edit the kubevirt config to avoid the error due to featuregate in developerConfiguration 
# @smitesh is working to resolve this

$ k edit  kubevirt -n kubevirt


spec:
  certificateRotateStrategy: {}
  configuration:
    developerConfiguration:
      featureGates:
      - Sidecar
  customizeComponents: {}
  imagePullPolicy: IfNotPresent
  workloadUpdateStrategy: {}

#################################################################################################

# Apply the sidecar config

cd /opt/user-apps/helm-charts/sidecar && k apply -f ub22_dp1.yaml

k get configmap

#################################################################################################

# Command to install and uninstall the application VM

# install
cd /opt/user-apps/helm-charts/helm-ub22_dp1 && helm install ub22vm .

# Verify deployment
k get pods -A
k get pv
k get pvc
k get vmi -A
k describe pod <ub22-vm pod>


# uninstall
cd /opt/user-apps/helm-charts/helm-ub22_dp1 && helm uninstall ub22vm

#################################################################################################
# Debug info

user@EdgeMicrovisorToolkit [ ~ ]$ k describe pod virt-launcher-ub22-vm-xdc9s
Name:             virt-launcher-ub22-vm-xdc9s
Namespace:        default
Priority:         0
Service Account:  default
Node:             <none>
Labels:           app.kubernetes.io/managed-by=Helm
                  app/name=ub22
                  kubevirt.io=virt-launcher
                  kubevirt.io/created-by=78983caa-698d-47f0-9c84-4e8ab5d7dfa4
                  vm.kubevirt.io/name=ub22-vm
Annotations:      descheduler.alpha.kubernetes.io/request-evict-only:
                  hooks.kubevirt.io/hookSidecars:
                    [{"args": ["--version", "v1alpha2"], "configMap": {"name": "sidecar-script-dp1", "key": "my_script.sh", "hookPath": "/usr/bin/onDefineDoma...
                  kubectl.kubernetes.io/default-container: compute
                  kubevirt.io/domain: ub22-vm
                  kubevirt.io/migrationTransportUnix: true
                  meta.helm.sh/release-name: ub22-vm
                  meta.helm.sh/release-namespace: default
                  post.hook.backup.velero.io/command: ["/usr/bin/virt-freezer", "--unfreeze", "--name", "ub22-vm", "--namespace", "default"]
                  post.hook.backup.velero.io/container: compute
                  pre.hook.backup.velero.io/command: ["/usr/bin/virt-freezer", "--freeze", "--name", "ub22-vm", "--namespace", "default"]
                  pre.hook.backup.velero.io/container: compute
Status:           Pending
IP:
IPs:              <none>
Controlled By:    VirtualMachineInstance/ub22-vm
Containers:
  compute:
    Image:      localhost:5000/virt-launcher:v1.5.0_DV
    Port:       <none>
    Host Port:  <none>
    Command:
      /usr/bin/virt-launcher-monitor
      --qemu-timeout
      312s
      --name
      ub22-vm
      --uid
      78983caa-698d-47f0-9c84-4e8ab5d7dfa4
      --namespace
      default
      --kubevirt-share-dir
      /var/run/kubevirt
      --ephemeral-disk-dir
      /var/run/kubevirt-ephemeral-disks
      --container-disk-dir
      /var/run/kubevirt/container-disks
      --grace-period-seconds
      15
      --hook-sidecars
      1
      --ovmf-path
      /usr/share/OVMF
      --run-as-nonroot
    Limits:
      devices.kubevirt.io/kvm:        1
      devices.kubevirt.io/tun:        1
      devices.kubevirt.io/vhost-net:  1
      ephemeral-storage:              2197483648
      hugepages-2Mi:                  12Gi
      intel.com/igpu:                 1
      intel.com/sriov-gpudevice:      1
      intel.com/udma:                 1
      intel.com/usb:                  1
      intel.com/vfio:                 1
      intel.com/x11:                  1
    Requests:
      cpu:                            300m
      devices.kubevirt.io/kvm:        1
      devices.kubevirt.io/tun:        1
      devices.kubevirt.io/vhost-net:  1
      ephemeral-storage:              1123741824
      hugepages-2Mi:                  12Gi
      intel.com/igpu:                 1
      intel.com/sriov-gpudevice:      1
      intel.com/udma:                 1
      intel.com/usb:                  1
      intel.com/vfio:                 1
      intel.com/x11:                  1
      memory:                         1418723328
    Environment:
      XDG_CACHE_HOME:   /var/run/kubevirt-private
      XDG_CONFIG_HOME:  /var/run/kubevirt-private
      XDG_RUNTIME_DIR:  /var/run
      POD_NAME:         virt-launcher-ub22-vm-xdc9s (v1:metadata.name)
    Mounts:
      /dev/hugepages from hugepages (rw)
      /dev/hugepages/libvirt/qemu from hugetblfs-dir (rw)
      /var/run/kubevirt from public (rw)
      /var/run/kubevirt-ephemeral-disks from ephemeral-disks (rw)
      /var/run/kubevirt-hooks from hook-sidecar-sockets (rw)
      /var/run/kubevirt-private from private (rw)
      /var/run/kubevirt-private/vmi-disks/bootdisk from bootdisk (rw)
      /var/run/kubevirt/container-disks from container-disks (rw)
      /var/run/kubevirt/hotplug-disks from hotplug-disks (rw)
      /var/run/kubevirt/sockets from sockets (rw)
      /var/run/libvirt from libvirt-runtime (rw)
  guest-console-log:
    Image:      localhost:5000/virt-launcher:v1.5.0_DV
    Port:       <none>
    Host Port:  <none>
    Command:
      /usr/bin/virt-tail
    Args:
      --logfile
      /var/run/kubevirt-private/78983caa-698d-47f0-9c84-4e8ab5d7dfa4/virt-serial0-log
      --socket-timeout
      312s
    Limits:
      cpu:     15m
      memory:  60M
    Requests:
      cpu:     5m
      memory:  35M
    Environment:
      VIRT_LAUNCHER_LOG_VERBOSITY:  2
    Mounts:
      /var/run/kubevirt-private from private (ro)
  hook-sidecar-0:
    Image:      localhost:5000/sidecar-shim:v1.5.0_DV
    Port:       <none>
    Host Port:  <none>
    Args:
      --version
      v1alpha2
    Environment:
      XDG_CACHE_HOME:   /var/run/kubevirt-private
      XDG_CONFIG_HOME:  /var/run/kubevirt-private
      XDG_RUNTIME_DIR:  /var/run
    Mounts:
      /usr/bin/onDefineDomain from sidecar-script-dp1 (rw,path="my_script.sh")
      /var/run/kubevirt-hooks from hook-sidecar-sockets (rw)
Readiness Gates:
  Type                                   Status
  kubevirt.io/virtual-machine-unpaused   True
Conditions:
  Type                                   Status
  PodScheduled                           False
  kubevirt.io/virtual-machine-unpaused   True
Volumes:
  private:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  public:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  sockets:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  virt-bin-share-dir:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  libvirt-runtime:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  ephemeral-disks:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  container-disks:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  bootdisk:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  ub22-bootdisk
    ReadOnly:   false
  hook-sidecar-sockets:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  hugepages:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     HugePages
    SizeLimit:  <unset>
  hugetblfs-dir:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  hotplug-disks:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
  sidecar-script-dp1:
    Type:        ConfigMap (a volume populated by a ConfigMap)
    Name:        sidecar-script-dp1
    Optional:    false
QoS Class:       Burstable
Node-Selectors:  kubernetes.io/arch=amd64
                 kubevirt.io/schedulable=true
Tolerations:     node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                 node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason            Age                From               Message
  ----     ------            ----               ----               -------
  Warning  FailedScheduling  26m                default-scheduler  0/1 nodes are available: 1 Insufficient ephemeral-storage, 1 Insufficient hugepages-2Mi, 1 Insufficient intel.com/igpu, 1 Insufficient i                                                                                          ntel.com/sriov-gpudevice, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
  Warning  FailedScheduling  15m (x2 over 20m)  default-scheduler  0/1 nodes are available: 1 Insufficient ephemeral-storage, 1 Insufficient hugepages-2Mi, 1 Insufficient intel.com/igpu, 1 Insufficient i                                                                                          ntel.com/sriov-gpudevice, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
user@EdgeMicrovisorToolkit [ ~ ]$


