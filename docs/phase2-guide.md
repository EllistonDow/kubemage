# Phase 2：平台基础服务实施指南

## 范围
- GitOps：Argo CD、仓库分层、SOPS/age 加密、CI 对接。
- 安全：Gatekeeper/Kyverno baseline、External Secrets Operator（ESO）+ Vault、kured、node-problem-detector。
- 监控与日志：kube-prometheus-stack（含 Thanos sidecar）、Loki + Tempo + Promtail、Alertmanager 通知。

## 先决条件
1. Phase 1 集群运行稳定，`fast-local-zfs` StorageClass 可用。
2. Git 托管（GitHub/GitLab）与容器镜像仓库（Harbor/OVH Registry）可访问。
3. Vault 或其他 Secret backend 已部署或可在本阶段同步搭建。

## 任务拆解
1. **GitOps 初始化**
   - 创建 `kubemage-gitops` 仓库（建议私有）。
   - 目录结构：
     ```
     infra/
       base/
       overlays/prod/
     platform/
       monitoring/
       security/
       gitops/
     tenants/
       <store>/
     clusters/
       kubemage-prod/
     ```
   - 将 `cluster/phase*` 目录中的模板转化为 `infra/base` 的 kustomize/helmfile，并由 Argo CD 管理。
   - 配置 SOPS（age）用于加密 values/secrets。
2. **部署 Argo CD**
   - 使用 `cluster/phase2/gitops/argocd-values.yaml` 通过 Helm 安装。
   - 创建 App of Apps（`argo-root.yaml`）指向 Git 仓库，实现自动同步。
3. **安全栈**
   - Gatekeeper + 约束：Pod 安全、label 规范、禁止特权容器。
   - Kyverno（可选）对 Namespace 注入默认 label、探针。
   - External Secrets Operator 连接 Vault，示例在 `cluster/phase2/security/eso-secretstore.yaml`。
   - kured + node-problem-detector，保证自动重启与硬件事件上报。
4. **可观测栈**
   - `cluster/phase2/monitoring/kube-prometheus-values.yaml`：启用 Thanos sidecar、OVH S3 远端存储、Alertmanager webhook。
   - Loki-stack values，配置对象存储；Tempo values，用于分布式 tracing。
   - Promtail DaemonSet 收集宿主及应用日志，写入 Loki。
5. **验证**
   - 通过 Argo CD UI 确认所有应用同步成功。
   - 检查 Gatekeeper constraint、ESO secret 拉取情况。
   - 执行告警与日志查询演练。

## 产出
- GitOps 仓库骨架 + 文档。
- 已运行的 Argo CD、Gatekeeper、ESO、kube-prometheus-stack、Loki+Tempo+Promtail、kured、node-problem-detector。
- Alerting/Logging 仪表盘与通知通道配置说明。

## 下一阶段
完成 Phase 2 后，可在 GitOps 下接入 Percona/OpenSearch/RabbitMQ/Valkey（Phase 3），并开始建立 CI/CD 流水线与站点模板。
