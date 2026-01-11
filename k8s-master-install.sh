#!/bin/bash
set -e

# Kubernetes Master Node Installation Script
# Tested on Ubuntu 22.04/24.04 and Debian 12

echo "=== Kubernetes Master Node Installation ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Variables
KUBERNETES_VERSION="1.31"
POD_NETWORK_CIDR="10.244.0.0/16"

echo "[1/8] Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "[2/8] Loading required kernel modules..."
cat <<MODULES | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES

modprobe overlay
modprobe br_netfilter

echo "[3/8] Configuring sysctl parameters..."
cat <<SYSCTL | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

sysctl --system

echo "[4/8] Installing containerd..."
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

echo "[5/8] Adding Kubernetes repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

echo "[6/8] Installing kubeadm, kubelet, and kubectl..."
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "[7/8] Initializing Kubernetes control plane..."
kubeadm init --pod-network-cidr=${POD_NETWORK_CIDR}

echo "[8/8] Configuring kubectl for current user..."
# Setup for root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Setup for the user who ran sudo
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    mkdir -p "$USER_HOME/.kube"
    cp /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.kube"
fi

echo ""
echo "=== Installing Flannel CNI ==="
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo ""
echo "=============================================="
echo "Kubernetes master node installation complete!"
echo "=============================================="
echo ""
echo "To add worker nodes, run this command on each worker:"
echo ""
kubeadm token create --print-join-command
echo ""
echo "Save the above command - you'll need it for worker nodes."
echo ""
echo "Verify cluster status with: kubectl get nodes"
