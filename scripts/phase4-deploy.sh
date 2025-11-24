#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
CHART="$ROOT/charts/magento"
VALUES=${1:-$ROOT/charts/magento/values-store-example.yaml}
RELEASE=${RELEASE:-store1}
NAMESPACE=${NAMESPACE:-store1}

if [[ ! -f "$VALUES" ]]; then
  echo "[phase4] values 文件不存在: $VALUES" >&2
  exit 1
fi

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl apply -f "$ROOT/cluster/phase4/namespaces/${NAMESPACE}.yaml"

helm upgrade --install "$RELEASE" "$CHART" -n "$NAMESPACE" -f "$VALUES"

cat <<'NEXT'
[phase4] 已触发 Helm 部署。请执行：
  1. kubectl get pods -n $NAMESPACE
  2. kubectl exec -n $NAMESPACE deploy/${RELEASE}-php -- php bin/magento setup:upgrade
  3. 验证 Ingress/SSL/CDN
NEXT
