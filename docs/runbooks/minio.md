# MinIO 共享对象存储

## 部署概览
- **Namespace / Release**：`object-storage` / `minio`
- **Chart**：`minio/minio`（v5.3.0，mode=distributed，replicas=4）
- **Image**：`quay.io/minio/minio:RELEASE.2024-10-13T22-27-07Z`（由 Helm chart 自动解析最新 tag）
- **持久化**：`local-path` StorageClass，四个 PVC（`export-minio-{0..3}`）每个 200 Gi，合计 800 Gi 原始容量
- **服务**：
  - API（S3 兼容）：`minio.object-storage.svc.cluster.local:9000`（ClusterIP `10.103.160.153`）
  - 控制台：`minio-console.object-storage.svc.cluster.local:9001`
- **Root 凭据（临时，仅供初始化）**
  - User：`kubemageadmin`
  - Password：`Qb5sXbrwg4mdgTkR0GptUMB+f1p77pb8`
  - 已写入 Secret：`minio`（`object-storage` namespace）
- **预创建 Buckets**：`demo-media`、`bdgy-media`、`shared-backup`

> ⚠️ 以上 root 账户仅供当前多租户共享数据层的引导阶段使用。上线前请创建每个站点独立的 IAM 用户，并通过 `mc admin user add` + policy 绑定来细化权限，同时轮换 root 凭据。

## 站点凭据与集成
- 已为 demo/bdgy 站点创建独立 IAM：`demoMediaUser`、`bdgyMediaUser`，策略仅允许访问各自 bucket（`demo-media`、`bdgy-media`）。
- 凭据写入各 namespace 的 `*-magento-secrets`（键名 `REMOTE_STORAGE_ACCESS_KEY` / `REMOTE_STORAGE_SECRET_KEY`），Helm Chart 会自动注入容器。
- Magento 端通过 `REMOTE_STORAGE_*` 环境变量构建 `app/etc/env.php`，并执行 `php bin/magento remote-storage:sync` 将 `pub/media` 同步到 MinIO。

## 访问方式
### 集群内服务
- Magento/备份组件直接使用 `http://minio.object-storage.svc.cluster.local:9000`，Access Key / Secret Key 即 root 或每站点专属 IAM。
- Ingress 尚未暴露，如需外部访问请后续接入 `ingress-nginx` 或通过 MetalLB/NodePort。

### 本地调试（端口转发）
```bash
# API
kubectl port-forward -n object-storage svc/minio 9000:9000

# Console
kubectl port-forward -n object-storage svc/minio-console 9001:9001
```
浏览器访问 `http://127.0.0.1:9001`, 使用 root 凭据登录。

### MinIO Client（mc）
```bash
export MINIO_ROOT_USER=kubemageadmin
export MINIO_ROOT_PASSWORD='Qb5sXbrwg4mdgTkR0GptUMB+f1p77pb8'

kubectl port-forward -n object-storage svc/minio 9000:9000

mc alias set kubemage http://127.0.0.1:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
mc ls kubemage
```

## 备份与监控
- `ops/shared-backup` CronJob（每日 03:00）通过 `scripts/shared-backup.sh` 同步 Percona PXC 全库 SQL 以及 OpenSearch 快照到 `shared-backup` PVC。
- `ops/shared-backup-upload` CronJob（每日 03:30）使用 MinIO Client `mc` 将 `/backups` 目录 mirror 到 `s3://demo-media/backups/<日期>/`，脚本会输出开始/结束日志便于排错。
- `gitops/platform/monitoring-addons` 中定义了 MinIO/Percona/OpenSearch/RabbitMQ/Valkey 的 exporters、ServiceMonitor 与 `kubemage-shared-services` 规则组，可在 Grafana 中直接看到共享数据层的健康状态，并由 Alertmanager 路由 `team=platform|storage` 告警。

## 下一步
1. **IAM 划分**：使用 `mc admin user add` / `mc admin policy add` 分配 `demo`、`bdgy`、`backup` 的独立 access key，并在各站点 Helm values 中引用。
2. **生命周期策略**：在 `shared-backup` bucket 上启用版本与对象生命周期（例如 30 天清理）。
3. **监控**：在 Prometheus 中抓取 `minio` Pod 的 `/minio/v2/metrics/cluster` 指标（参考 Phase3 监控任务）。
4. **备份**：结合 restic / Velero，使用 `shared-backup` 作为镜像站点备份的远端仓库。  
