# Artifacts 归档说明

- `phase1/`: kubeadm init 日志、sonobuoy 报告 (`sonobuoy-results.tar.gz`)、kubelet 配置、VIP 配置截图。
- `phase2/`: Argo CD 同步截图、Grafana dashboard 导出、Gatekeeper 违规记录。
- `phase3/`: Percona/OpenSearch/RabbitMQ/Valkey 备份日志、S3 清单、监控截图。
- `phase4/`: Helm release history、性能测试报告、CDN 配置。
- `phase5/`: 节点扩容日志、Longhorn/Velero 状态、灾备演练记录、SLO 报表。

统一命名：`YYYYMMDD-HHMM-description.ext`，并在每个阶段目录下附 `README.md` 简述内容。
