#!/usr/bin/env bash
set -euo pipefail
WORKDIR=$(cd -- "$(dirname "$0")/.." && pwd)
cd "$WORKDIR/cluster/phase1"

info() { echo "[phase1] $*"; }

info "使用 kubeadm config: kubeadm-config.yaml"
info "请先运行 host-init.sh 并替换 VIP/IP"
info "执行 kubeadm init..."
cat <<'CMD'
sudo kubeadm init --config kubeadm-config.yaml --upload-certs
mkdir -p $$HOME/.kube
sudo cp /etc/kubernetes/admin.conf $$HOME/.kube/config
sudo chown $$(id -u):$$(id -g) $$HOME/.kube/config
CMD

info "安装 kube-vip（请根据 docs/phase1-guide.md 修改 VIP/接口）"

info "安装 Cilium"
helm repo add cilium https://helm.cilium.io/ >/dev/null
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.15.5 \
  -f cilium-values.yaml

info "安装 MetalLB"
kubectl get ns metallb-system >/dev/null 2>&1 || kubectl create ns metallb-system
helm repo add metallb https://metallb.github.io/metallb >/dev/null
helm upgrade --install metallb metallb/metallb -n metallb-system --version 0.14.5
kubectl apply -f metallb-config.yaml

info "安装 OpenEBS ZFS"
helm repo add openebs https://openebs.github.io/charts >/dev/null
helm upgrade --install openebs openebs/openebs -n openebs --create-namespace \
  --version 3.10.0 -f openebs-values.yaml

info "Phase1 主要组件部署完成，按 docs/phase1-guide.md 验证"
