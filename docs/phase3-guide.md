# Phase 3：依赖服务落地指南

## 范围
- Percona MySQL 8.4（Percona Operator for MySQL / PXC）。
- OpenSearch 2.19（OpenSearch Operator）。
- RabbitMQ 4.1（RabbitMQ Cluster Operator）。
- Valkey 8（Bitnami/Redis chart + Sentinel）。
- Web Edge：Varnish、Nginx Ingress Controller、PHP-FPM 镜像流水线准备。

## 目标
1. 在 Kubernetes 上部署上述核心依赖，并完成备份/监控/告警对接。
2. 为未来第二台裸机上线时的副本扩容预置 AntiAffinity/TopologySpread。
3. 输出 Runbook：备份恢复、扩缩容、常见故障排查。

## 前提
- Phase 2 GitOps/监控/安全栈运行正常，ESO 能从 Vault 取密钥。
- `fast-local-zfs` StorageClass 可用，S3/对象存储凭证可用。
- Harbor/Registry 已建立并可推送自定义镜像。

## 流程概览与指令
1. **Percona Operator（MySQL）**
   - 安装：`helm repo add percona https://percona.github.io/percona-helm-charts && helm install pxc-operator percona/pxc-operator -n databases -f cluster/phase3/percona/percona-operator-values.yaml`.
   - 创建 Secret（建议由 ESO 下发）后，`kubectl apply -f cluster/phase3/percona/percona-cluster.yaml`.
   - 备份配置：`kubectl apply -f cluster/phase3/percona/s3-backup-secret.yaml`.
2. **OpenSearch Operator**
   - 安装：`helm repo add opensearch-operator https://opster.github.io/opensearch-k8s-operator`.
   - `helm install opensearch-operator opensearch-operator/opensearch-operator -n search`.
   - `kubectl apply -f cluster/phase3/opensearch/`.
3. **RabbitMQ Operator**
   - 安装：`kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.6.0/cluster-operator.yml`.
   - `kubectl apply -n messaging -f cluster/phase3/rabbitmq/`.
4. **Valkey（Bitnami Helm）**
   - `helm repo add bitnami https://charts.bitnami.com/bitnami`.
   - 准备 Secret 后 `helm install valkey bitnami/redis -n cache -f cluster/phase3/valkey/valkey-values.yaml`.
5. **Edge**
   - `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`，`helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx -f cluster/phase3/edge/nginx-ingress-values.yaml`.
   - Varnish chart（可自建 Helm）：`helm upgrade --install varnish charts/varnish -n edge -f cluster/phase3/edge/varnish-values.yaml`.
   - 准备 `varnish-vcl` Secret 与 Phase 4 镜像流水线（见 `docs/edge-build.md`）。

## 交付清单
- `cluster/phase3/*` 目录下的 Helm values/CR YAML。
- Runbooks：`runbooks/mysql-backup.md`, `runbooks/opensearch-backup.md`, `runbooks/rabbitmq.md`, `runbooks/valkey.md`, `runbooks/edge.md`。
- 镜像构建说明 `docs/edge-build.md`。
- Phase 3 验证报告：备份任务成功截图、指标/日志接入说明（执行后填写）。
