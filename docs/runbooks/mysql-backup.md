# Percona MySQL 备份/恢复 Runbook

## 每日例行
1. 确认 `percona-backup` CronJob 成功：`kubectl get perconabackups -n databases`。
2. 检查 S3 存储桶 `kubemage-mysql` 是否有最新目录。
3. 确认 `pitr` Pod 正常，将 binlog 上传到 S3。

## 手动全量备份
```bash
kubectl apply -f percona-manual-backup.yaml
kubectl describe perconabackup magento-manual -n databases
```
`percona-manual-backup.yaml`：
```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterBackup
metadata:
  name: magento-manual
  namespace: databases
spec:
  pxcCluster: magento-db
  storageName: s3-magento
```

## 恢复流程（单节点）
1. 停止应用写入（Argo CD scale Magento 部署到 0）。
2. 创建恢复对象：
```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterRestore
metadata:
  name: magento-restore
  namespace: databases
spec:
  pxcCluster: magento-db
  backupName: magento-manual
```
3. 监控 `kubectl get pods -n databases -l backup.percona.com/type=restore`。
4. 验证数据后再开放应用。

## PITR（时间点恢复）
1. 找到目标时间戳（UTC）。
2. 执行：
```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterRestore
metadata:
  name: magento-restore-pitr
  namespace: databases
spec:
  pxcCluster: magento-db
  backupName: magento-manual
  pitr:
    date: "2025-01-15T10:05:00Z"
```
3. 同步验证。

## 常见问题
- **Backup Failed**：检查 s3 credentials secret、网络连通、S3 ACL。
- **PITR 停止**：确认 `timeBetweenUploads` 是否过高，必要时调低。
