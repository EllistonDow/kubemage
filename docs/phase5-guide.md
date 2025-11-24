# Phase 5：运维、扩容与灾备

## 目标
1. 第二台裸金属（bm-b）加入集群，形成多节点 control-plane + data plane。
2. 引入分布式存储（Longhorn 或 Rook-Ceph），实现跨节点 PVC 迁移。
3. 完成季度备份/恢复演练、容量规划、灾难恢复 Runbook。
4. 建立升级策略（Kubernetes、Magento、Operators）与 SLO/SLA 监控。

## 关键任务
1. **节点扩容**
   - 按 Phase0/1 脚本初始化 bm-b。
   - `kubeadm join --control-plane`，验证 etcd 成员、kube-vip 漂移。
   - 为 StatefulSet 添加 `podAntiAffinity`、`topologySpreadConstraints`，扩容副本。
2. **分布式存储**
   - 安装 Longhorn（`helm install longhorn longhorn/longhorn -n longhorn-system`），或 Rook-Ceph（若需要对象/块存储）。
   - 为关键 PVC（数据库、Valkey、RabbitMQ）规划迁移策略（先创建快照 -> 新 StorageClass -> Velero/Restic 迁移）。
3. **备份/恢复演练**
   - MySQL：PXC PITR 恢复至 staging namespace。
   - OpenSearch：snapshot restore。
   - RabbitMQ/Valkey：导入导出。
   - Velero：`velero restore create --from-backup <backup>`。
4. **容量与性能**
   - 使用 KEDA + Prometheus 指标，建立自动扩容策略。
   - 跑压测（k6/JMeter）并记录 QPS、延迟、资源占用，更新 `docs/capacity-plan.md`。
5. **升级策略**
   - Kubernetes minor：N-1，使用 `kubectl cordon/drain` + `kubeadm upgrade`。
   - Magento patch：预生产环境验证 -> GitOps promotion。
   - Operator：启用 canary namespace。
6. **SRE 运行机制**
   - SLO：如 `availability >= 99.9%`，`checkout latency < 2s`。
   - Error Budget 汇报，incident 模板 `docs/runbooks/incident-template.md`。

## 输出
- `cluster/phase5/*`: Longhorn/Rook manifests、anti-affinity patches、Velero schedules。
- Runbooks：`runbooks/incident-template.md`, `runbooks/storage-migration.md`, `runbooks/upgrade.md`。
- Capacity & SLO 文档：`docs/capacity-plan.md`, `docs/slo.md`。

## 完成标准
- 两台裸机稳定运行 >30 天无数据丢失。
- 所有有状态组件具备 >=2 副本并跨节点部署。
- 分布式存储上线并承载至少一类关键数据。
- 备份/恢复演练记录齐备，Incident 模板生效。
