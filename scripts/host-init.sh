#!/usr/bin/env bash
set -euo pipefail

# 宿主机初始化脚本骨架：Ubuntu 24.04 LTS 裸机（无 PVE）。
# 使用前请根据实际网络/FQDN/磁盘调整变量。

HOSTNAME_FQDN="bm-a.example.com"
TIMEZONE="UTC"
ZFS_DATASET_PV="rpool/k8s/pv"
HOLD_KERNEL_PKGS=(linux-image-generic linux-headers-generic)
BASE_PACKAGES=(curl jq gnupg lsb-release ca-certificates apt-transport-https chrony zip unzip git htop nvme-cli zfsutils-linux)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[FATAL] 必须使用 root 执行" >&2
    exit 1
  fi
}

run() {
  echo "[RUN] $*"
  "$@"
}

configure_hostname() {
  run hostnamectl set-hostname "${HOSTNAME_FQDN}"
}

set_timezone() {
  run timedatectl set-timezone "${TIMEZONE}"
  run systemctl enable --now chrony
}

apt_setup() {
  run apt-get update
  run apt-get -y install software-properties-common
  run apt-get -y upgrade
  run apt-get -y install "${BASE_PACKAGES[@]}"
  DEBIAN_FRONTEND=noninteractive run apt-get -y dist-upgrade
  for pkg in "${HOLD_KERNEL_PKGS[@]}"; do
    run apt-mark hold "$pkg"
  done
}

swap_disable() {
  if swapon --show | grep -q .; then
    run swapoff -a
  fi
  sed -i.bak '/swap/d' /etc/fstab
}

resolved_stub_disable() {
  local conf=/etc/systemd/resolved.conf
  if ! grep -q '^DNSStubListener=no' "$conf"; then
    sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' "$conf"
  fi
  systemctl restart systemd-resolved
}

kernel_sysctl() {
  cat <<'SYSCTL' >/etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 10
SYSCTL
  modprobe overlay
  modprobe br_netfilter
  sysctl --system
}

containerd_install() {
  if ! command -v containerd >/dev/null 2>&1; then
    run apt-get -y install containerd
  fi
  run mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  run systemctl enable --now containerd
}

kubernetes_repo() {
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
  cat <<'LIST' >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ / 
LIST
  run apt-get update
  run apt-get -y install kubelet kubeadm kubectl
  run apt-mark hold kubelet kubeadm kubectl
}

zfs_dataset_prep() {
  if ! zfs list "$ZFS_DATASET_PV" >/dev/null 2>&1; then
    echo "[WARN] 数据集 $ZFS_DATASET_PV 不存在，跳过"
    return
  fi
  run zfs set compression=lz4 "$ZFS_DATASET_PV"
  run zfs set atime=off "$ZFS_DATASET_PV"
}

ufw_baseline() {
  if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 6443/tcp    # kube-apiserver
    ufw allow 10250/tcp   # kubelet
    ufw --force enable
  fi
}

main() {
  require_root
  configure_hostname
  set_timezone
  apt_setup
  swap_disable
  resolved_stub_disable
  kernel_sysctl
  containerd_install
  kubernetes_repo
  zfs_dataset_prep
  ufw_baseline
  echo "[DONE] 宿主机初始化完成；请继续执行 Phase 1。"
}

main "$@"
