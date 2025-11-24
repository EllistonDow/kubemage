# OpenSearch 备份/恢复 Runbook

## 日常检查
1. 查看 `snapshot` 状态：
```bash
kubectl exec -n search sts/magento-search-masters-0 -- \
  curl -s -k -u admin:${OPENSEARCH_PASSWORD} \
  https://localhost:9200/_snapshot/s3-magento/_all?pretty | jq '.snapshots[-1]' 
```
2. 监控 ILM：`GET _ilm/explain/magento-*`。

## 手动快照
```bash
POST _snapshot/s3-magento/manual-$(date +%F)
{
  "indices": "magento-*",
  "ignore_unavailable": true
}
```

## 恢复
1. 将集群置于红色只读：`PUT _cluster/settings {"persistent":{"cluster.blocks.read_only":true}}`。
2. 执行：
```bash
POST _snapshot/s3-magento/manual-2025.01.15/_restore
{
  "indices": "magento-*",
  "include_aliases": true,
  "ignore_unavailable": true
}
```
3. 恢复完成后 `PUT _cluster/settings {"persistent":{"cluster.blocks.read_only":null}}`。
4. 验证搜索功能、Dashboards 仪表。

## 故障排查
- `repository_exception`: 检查 S3 secret、endpoint、防火墙。
- `snapshot_in_progress_exception`: 使用 `GET _snapshot/_status` 确认是否仍在运行，必要时 `DELETE _snapshot/<repo>/<snapshot>`。
