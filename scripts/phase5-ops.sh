#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
case "${1:-help}" in
  join-node)
    echo "参考 docs/phase5-node-expand.md 执行 kubeadm join"
    ;;
  longhorn)
    helm repo add longhorn https://charts.longhorn.io >/dev/null
    helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace \
      -f "$ROOT/cluster/phase5/storage/longhorn-values.yaml"
    ;;
  velero)
    echo "应用 Velero schedule"
    kubectl apply -f "$ROOT/cluster/phase5/storage/velero-schedule.yaml"
    ;;
  status)
    kubectl get nodes -o wide
    kubectl get pods -A | head -n 50
    ;;
  *)
    cat <<'USAGE'
用法: phase5-ops.sh <command>
命令:
  join-node   - 参考 docs/phase5-node-expand，添加新的控制面节点
  longhorn    - 安装/升级 Longhorn
  velero      - 应用 Velero 备份计划
  status      - 查看节点/关键 Pod 状态
USAGE
    ;;
esac
