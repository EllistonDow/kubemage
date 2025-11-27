# Magento 2.4.8 维护基线

> 适用于 Kubemage 的 Kubernetes 多站点集群。目标是让每次上线/迁移前都有统一的“入场检查表”，并把日常维护节奏（分钟/每天/每周/每月）标准化。

## 1. Cron 运行策略（每分钟）
- **主 Cron**：所有站点必须每分钟执行 `php bin/magento cron:run`。Helm 默认的 `cron-main` CronJob 已调整为 `*/1 * * * *`，如需额外分组（如 `index`、`default`）可通过 values 追加。
- **容器环境命令示例**：
  ```bash
  kubectl exec -n <ns> deploy/<site>-magento-php -- \
    php -d memory_limit=2G bin/magento cron:run
  ```
- **常见问题**：cron 队列阻塞会堆积在 `cron_schedule` 表，可通过 `select status, count(*) from cron_schedule group by 1;` 检查。

## 2. 每日 Checklist
| 项目 | 操作 | 说明 |
| --- | --- | --- |
| Cron 健康 | `kubectl logs job/<site>-magento-cron-main-<ts>` | 确认上一小时内至少执行 60 次，无报错 |
| 队列 backlog | `kubectl exec -n <ns> deploy/<site>-magento-php -- bin/magento queue:consumers:list` | `Messages` 列应该快速归零 |
| Cache & Redis | `kubectl exec valkey-0 -n cache -- redis-cli info memory` | 确认内存 < 80%，必要时 `FLUSHDB` 指定站点 DB |
| 备份 Cron | `kubectl get jobs -n ops -l job-name=shared-backup` | 03:00 的 FULL 备份、03:30 的上传任务应成功 |
| Blackbox | 查看 Alertmanager 或 Grafana | `demo-store`/`bdgy-store` 探针无 5xx/超时 |

## 3. 每周 Checklist
1. **全量 reindex**：
   ```bash
   kubectl exec -n <ns> deploy/<site>-magento-php -- bin/magento indexer:reindex
   ```
2. **静态资源校验**：确认 `pub/static/deployed_version.txt` 存在，必要时运行 `setup:static-content:deploy -f`。
3. **媒体/MinIO**：对比 `pub/media` 与 MinIO Bucket 对象数（`mc du`），必要时 `php bin/magento remote-storage:sync`。
4. **OpenSearch snapshot**：检查 `ops/shared-backup` CronJob 产物或通过 `_cat/snapshots` 确认成功。

## 4. 每月 Checklist
| 项目 | 操作 |
| --- | --- |
| 数据库优化 | `ANALYZE TABLE` / `OPTIMIZE TABLE` 针对日志/报表表，或使用 Percona Toolkit |
| 凭证轮换 | 最少每季度轮换 RabbitMQ/Redis/MinIO 访问密钥，更新 SOPS Secret 并 Argo 同步 |
| SSL & Base URL | 检查证书到期时间（`kubectl exec ingress-nginx ... openssl x509 -enddate`），确认 `base-url` 与 DNS 匹配 |
| 站点验收 | 执行 smoke test：前台加载、搜索、下单；后台登录、订单列表、产品编辑 |

## 5. 应急/Keep-Calm 脚本
当遇到缓存损坏或 500 错误，可执行 `scripts/magento-keep-calm.sh`（或手动运行以下清单）：
```bash
php bin/magento maintenance:enable
rm -rf generated/* var/{cache,page_cache,view_preprocessed,di}/* pub/static/*
php bin/magento setup:upgrade
php bin/magento setup:di:compile
php bin/magento setup:static-content:deploy -f -j 8
php bin/magento indexer:reindex
php bin/magento cache:clean && php bin/magento cache:flush
php bin/magento maintenance:disable
```
在 Kubernetes 中可通过 `kubectl exec -n <ns> deploy/<site>-magento-php -- bash -c '<commands>'` 执行。

## 6. 备份与恢复要点
- **Percona**：`shared-backup` CronJob 03:00 执行 `mysqldump`，文件写入 `/backups/percona` 并同步到 MinIO `s3://demo-media/backups/<date>/`。
- **OpenSearch**：`shared-backup` CronJob 创建临时 snapshot repository，并上传 tar 包到 `/backups/opensearch`。
- **媒体**：MinIO 作为主存储，站点 Pod 启动时会将 `pub/media` 挂载到 PVC（如需恢复，先同步 MinIO -> PVC）。

## 7. 监控与告警
- Prometheus 通过 kube-prometheus-stack 收集 Kubernetes / Magento 依赖指标，黑盒 exporter 负责站点 5xx/超时。
- Alertmanager 配置了 Telegram receiver（`team=platform`），下列告警必须响应：`StoreEndpointDown/Slow`、`SharedBackupJobFailed`、`RabbitMQQueueBacklog`、`ValkeyMemoryPressure`、`PrometheusRuleFailures`。

> 建议在每次正式上线前，把“每日 Checklist”跑一遍，并在周/月维护窗口中记录执行结果（可写入 ops runbook 或 issue）。
