# Start the K8* scripts only once
if [ ! -f "/var/lib/rancher/k3s_status" ]; then
    mkdir -p /tmp/k3s-artifacts/
    tar -xf /opt/sen-k3s-package.tar.gz -C /tmp/k3s-artifacts/

    cd /tmp/k3s-artifacts/

    chmod +x sen-k3s-installer.sh

    bash sen-k3s-installer.sh
else
    echo "k3s is already installed and running. Skipping installation." | sudo tee /var/log/cluster-init.log | sudo tee /dev/tty1
    cd /etc/cloud/
    chmod +x k3s-setup-post-reboot.sh
    bash k3s-setup-post-reboot.sh
fi
