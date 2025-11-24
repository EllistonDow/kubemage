#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT/cluster/phase3"

info() { echo "[phase3] $*"; }

info "部署 Percona Operator"
helm repo add percona https://percona.github.io/percona-helm-charts >/dev/null
helm upgrade --install pxc-operator percona/pxc-operator -n databases --create-namespace \
  -f percona/percona-operator-values.yaml
kubectl apply -f percona/s3-backup-secret.yaml
kubectl apply -f percona/percona-cluster.yaml

info "部署 OpenSearch Operator + 集群"
helm repo add opensearch-operator https://opster.github.io/opensearch-k8s-operator >/dev/null
helm upgrade --install opensearch-operator opensearch-operator/opensearch-operator -n search --create-namespace
kubectl apply -f opensearch/s3-secret.yaml
kubectl apply -f opensearch/opensearch-cluster.yaml

info "部署 RabbitMQ Operator + 集群"
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.6.0/cluster-operator.yml
kubectl apply -f rabbitmq/rabbitmq-users-secret.yaml
kubectl apply -f rabbitmq/rabbitmq-cluster.yaml
kubectl apply -f rabbitmq/rabbitmq-policies.yaml

info "部署 Valkey (Bitnami)"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
kubectl apply -f valkey/valkey-auth-secret.yaml
helm upgrade --install valkey bitnami/redis -n cache --create-namespace \
  -f valkey/valkey-values.yaml

info "部署 Edge 组件"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  -f edge/nginx-ingress-values.yaml
kubectl apply -n edge --dry-run=client -o yaml -f /dev/null >/dev/null 2>&1 || kubectl create ns edge
kubectl apply -n edge -f edge/varnish-vcl-secret.yaml
# 假设 varnish chart 存在；如使用自定义 chart，请替换
# helm upgrade --install varnish ./charts/varnish -n edge -f edge/varnish-values.yaml

info "Phase3 依赖部署完成，下一步：按照 runbooks 执行备份/监控验证"
