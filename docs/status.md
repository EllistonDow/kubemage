# Kubemage Blueprint 状态 (2025-11-26)

| Phase | 状态 | 关键交付 | 下一动作 |
| --- | --- | --- | --- |
| Phase 0 | 资料齐备 | `scripts/host-init.sh`, `docs/phase-0-checklist.md` | 在 bm-a 执行脚本并记录结果 |
| Phase 1 | 模板完成 | kubeadm config、Cilium/MetalLB/OpenEBS values、`docs/phase1-guide.md` | 替换 VIP/IP，按指南初始化集群 |
| Phase 2 | 模板完成 | GitOps/Argo、监控、安全 manifests + runbooks | 创建 GitOps 仓库、部署 Argo、验证 ESO/监控 |
| Phase 3 | 进行中 | Percona/OpenSearch/RabbitMQ/Valkey/Edge 配置、备份 runbook | MinIO 已拆分 demo/bdgy IAM（`demoMediaUser`、`bdgyMediaUser`），`scripts/shared-backup.sh` / `shared-monitor.sh` 已支持 Kubernetes 集群（`SHARED_BACKEND=k8s` 自动选择 Pod），形成可回滚的 Percona/OpenSearch 备份链路；下一步将备份脚本挂到 CronJob/Alertmanager 并补充 Valkey/RabbitMQ 监控指标 |
| Phase 4 | 持续推进 | Magento Helm chart、Namespace policies、部署 runbook | demo/bdgy 站点通过 `ingress-nginx` + Let's Encrypt 上线（`magento.k8s.bdgyoo.com` / `bdgy.k8s.bdgyoo.com`），Chart 已内建 Varnish Deployment/Service 并默认在 namespace 内暴露 `varnish:6081`、支持 `varnish.purgeCIDRs` 及「404 不缓存」策略，Argo CD 根应用迁移到 GitHub HTTPS 并待最终 Sync（`platform/`→`gitops/platform`），站点 Helm values 现默认部署 `async.operations.all` + 产品属性消费者（`product_action_attribute.*`），Namespace NetworkPolicy 放开 kube-system DNS，Braintree 模块关闭、Composer exclude generated 配合 `magento-builder.sh` 产出 PVC 缓存；下一步将 RabbitMQ 监控/KEDA、证书轮换流程写入 SOP |
| Phase 5 | 模板完成 | Longhorn/Velero configs、扩容/升级 runbooks、SLO/容量文档 | 引入第二台裸机、上线分布式存储、执行演练 |

所有文档位于 `docs/`，可在 Git 仓库中提交并推送。执行过程中请将验证结果（sonobuoy、备份、性能测试）存入 `artifacts/` 目录（尚待创建）。
