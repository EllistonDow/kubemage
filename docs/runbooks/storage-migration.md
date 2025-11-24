# 存储迁移 Runbook（LocalPV -> Longhorn）

1. **准备**
   - Longhorn 集群已安装并可用 (`kubectl -n longhorn-system get pods`).
   - 创建新的 StorageClass `longhorn`（Longhorn 默认）。
2. **PVC 迁移步骤（以 Magento Web 媒体 PVC 为例）**
   1. `kubectl annotate pvc media-pvc kubernetes.io/change-csi-driver=true`。
   2. `velero backup create media-pvc-$(date +%s) --include-resources pvc,pv --selector app=magento-web`。
   3. 创建 `VolumeSnapshot`（若使用 CSI snapshot）。
   4. 新建 PVC YAML，指定 `storageClassName: longhorn`。
   5. `kubectl apply -f new-pvc.yaml` 并等待 Bound。
   6. 使用 `rsync` Job 或 `kubectl cp` 将数据从旧 Pod 复制到新 PVC。
   7. 更新 Deployment 挂载新 PVC，观察 Pod 重建。
   8. 验证数据完整性（媒体文件、checksum）。
3. **数据库迁移**
   - 对 PXC：使用 `PerconaXtraDBCluster` 新增实例并指定 Longhorn StorageClass，完成后缩容旧实例。
4. **回滚**
   - 如新 PVC 异常，使用 Velero Restore + 原 PVC YAML 恢复。
5. **记录**
   - 在 `docs/capacity-plan.md` 标记迁移完成日期。
