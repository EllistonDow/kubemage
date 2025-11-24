# Artifacts 归档说明

- `phase1/`: kubeadm init 日志、sonobuoy 报告 (`sonobuoy-results.tar.gz`)、kubelet 配置、VIP 配置截图。
- `phase2/`: Argo CD 同步截图、Grafana dashboard 导出、Gatekeeper 违规记录。
- `phase3/`: Percona/OpenSearch/RabbitMQ/Valkey 备份日志、S3 清单、监控截图。
- `shared-backups/`: `scripts/shared-backup.sh` 生成的本地 Percona/OpenSearch 备份（sql.gz / tar.gz）。
- `opensearch-snapshots/`: 供 OpenSearch 快照使用的挂载目录，脚本会在此生成临时仓库再打包。
- `phase4/`: Helm release history、性能测试报告、CDN 配置。
- `phase5/`: 节点扩容日志、Longhorn/Velero 状态、灾备演练记录、SLO 报表。

统一命名：`YYYYMMDD-HHMM-description.ext`，并在每个阶段目录下附 `README.md` 简述内容。
