# Valkey Runbook

## 日常
- `kubectl get pods -n cache -l app.kubernetes.io/name=redis`。
- Sentinel 状态：
```bash
kubectl exec -n cache svc/valkey -c sentinel -- redis-cli -p 26379 INFO Sentinel
```
- Metrics：Prometheus `redis_exporter` 指标（连接/内存/命中率）。

## 主从切换
1. 通过 Sentinel CLI：`SENTINEL failover magento`。
2. 确认新的主节点：`SENTINEL get-master-addr-by-name magento`。
3. 更新 Magento 配置（若使用 Service/hostname，无需变更）。

## 扩容
- 修改 `valkey-values.yaml` 中 `replica.replicaCount` 并通过 Helm 升级。
- Operator 会新增副本；注意 `topologySpread`（可在 Phase 4 添加）。

## 备份
- 使用 `redis-cli --rdb /data/dump.rdb` 并上传到对象存储。
- 建议 cron Job：`kubectl create job --from=cronjob/valkey-rdb-backup backup-$(date +%s)`。

## 故障
- `Master not reachable`: 检查网络策略/Cilium，确认 Pod/Node 状态。
- `OOM`：查看 `kubectl top pod`，调整 requests/limits 或启用 `maxmemory-policy allkeys-lru`。
