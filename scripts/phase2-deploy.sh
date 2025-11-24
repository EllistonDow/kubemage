#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT/cluster/phase2"

info() { echo "[phase2] $*"; }

info "确保 kubeconfig 可用，开始部署 Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version 5.53.0 -f gitops/argocd-values.yaml

info "应用 Argo Root Application"
kubectl apply -f gitops/argo-root.yaml

info "部署 Gatekeeper 模板和约束"
kubectl apply -f security/gatekeeper-pss-template.yaml
kubectl apply -f security/gatekeeper-pss-constraint.yaml

info "部署 External Secrets Operator 资源（需先安装 ESO Helm Chart）"
kubectl apply -f security/eso-secretstore.yaml
kubectl apply -f security/external-secret-sample.yaml

info "部署 kured、node-problem-detector（需提前安装 helm chart/manifest）"
helm repo add kured https://kubereboot.github.io/charts >/dev/null
helm upgrade --install kured kubereboot/kured -n kube-system -f security/kured-values.yaml
kubectl apply -f security/node-problem-detector-config.yaml
kubectl apply -f security/node-problem-detector.yaml

info "部署监控栈"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --version 61.2.0 \
  -f monitoring/kube-prometheus-values.yaml

info "部署 Loki / Tempo"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm upgrade --install loki grafana/loki-stack -n monitoring \
  --version 2.9.11 -f monitoring/loki-values.yaml
helm upgrade --install tempo grafana/tempo -n monitoring \
  --version 1.10.2 -f monitoring/tempo-values.yaml

info "Phase2 组件已部署；请在 Argo CD 中确认同步状态并更新 docs/runbooks"
