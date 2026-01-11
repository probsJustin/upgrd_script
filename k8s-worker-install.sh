#!/bin/bash
set -e

# Kubernetes Worker Node Installation Script
# Tested on Ubuntu 22.04/24.04 and Debian 12

echo "=== Kubernetes Worker Node Installation ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Variables
KUBERNETES_VERSION="1.31"

echo "[1/6] Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "[2/6] Loading required kernel modules..."
cat <<MODULES | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES

modprobe overlay
modprobe br_netfilter

echo "[3/6] Configuring sysctl parameters..."
cat <<SYSCTL | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

sysctl --system

echo "[4/6] Installing containerd..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# Install containerd
apt-get install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "[5/6] Adding Kubernetes repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

echo "[6/6] Installing kubeadm and kubelet..."
apt-get update
apt-get install -y kubelet kubeadm
apt-mark hold kubelet kubeadm

systemctl enable kubelet

echo ""
echo "=============================================="
echo "Kubernetes worker node installation complete!"
echo "=============================================="
echo ""
echo "To join this node to the cluster, run the join command"
echo "from the master node output. It looks like:"
echo ""
echo "  kubeadm join <master-ip>:6443 --token <token> \\"
echo "      --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo "If you lost the join command, run this on the master node:"
echo "  kubeadm token create --print-join-command"
echo ""
