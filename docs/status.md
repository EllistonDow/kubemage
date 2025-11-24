# Kubemage Blueprint 状态 (2025-11-22)

| Phase | 状态 | 关键交付 | 下一动作 |
| --- | --- | --- | --- |
| Phase 0 | 资料齐备 | `scripts/host-init.sh`, `docs/phase-0-checklist.md` | 在 bm-a 执行脚本并记录结果 |
| Phase 1 | 模板完成 | kubeadm config、Cilium/MetalLB/OpenEBS values、`docs/phase1-guide.md` | 替换 VIP/IP，按指南初始化集群 |
| Phase 2 | 模板完成 | GitOps/Argo、监控、安全 manifests + runbooks | 创建 GitOps 仓库、部署 Argo、验证 ESO/监控 |
| Phase 3 | 模板完成 | Percona/OpenSearch/RabbitMQ/Valkey/Edge 配置、备份 runbook | 按顺序部署 Operator + CR，执行备份演练 |
| Phase 4 | 模板完成 | Magento Helm chart、Namespace policies、部署 runbook | 构建镜像、部署首个站点、接入 CDN |
| Phase 5 | 模板完成 | Longhorn/Velero configs、扩容/升级 runbooks、SLO/容量文档 | 引入第二台裸机、上线分布式存储、执行演练 |

所有文档位于 `docs/`，可在 Git 仓库中提交并推送。执行过程中请将验证结果（sonobuoy、备份、性能测试）存入 `artifacts/` 目录（尚待创建）。
