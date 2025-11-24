# Velero 备份/恢复 Runbook

## 日常
- `kubectl get schedules -n velero`
- `velero backup get` 确认最新状态。
- 监控 `velero` Namespace Pod 日志。

## 手动备份
```bash
velero backup create manual-$(date +%s) \
  --include-namespaces store1,databases,messaging
```

## 恢复
1. `velero restore create restore-$(date +%s) --from-backup <backup-name>`。
2. 观察 `velero restore get` 状态。
3. 若需单 Namespace：`--include-namespaces store1`。

## Tips
- 对于本地 PV，确保启用 CSI snapshot 或 restic。
- 恢复前考虑 `kubectl delete namespace <ns>` 清理旧资源。
