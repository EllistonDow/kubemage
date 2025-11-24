# GitOps 架构设计

## 仓库规划
- `kubemage-gitops`：存放所有 Kubernetes 声明式资源。
  - `clusters/kubemage-prod/`：App of Apps（Argo Root）与集群级 overlay。
  - `infra/`：CNI、MetalLB、StorageClass、kube-vip 等基础设施。
  - `platform/`：GitOps、监控、安全、备份等组件。
  - `tenants/<store>/`：各 Magento 站点的 Helm release/values。
  - `modules/helm/`：自定义 Helm chart（Magento、Varnish 等）。
- `kubemage-apps`：Magento 应用源码与 Dockerfile/Helm chart。

## 工作流程
1. 开发者提交 PR -> CI 执行 `helm lint`、`kubeconform`、`sops decrypt --verify`。
2. 合并 `main` 后，Argo CD 自动同步至集群，遵循 `sync-wave` 控制顺序：
   1. infra
   2. platform
   3. tenants
3. 回滚：通过 `git revert` 触发 Argo CD 回滚；紧急情况在 Argo UI 手动 `sync to previous revision`。

## 密钥管理
- 使用 `SOPS + age` 加密 `*.enc.yaml`。
- `argocd-repo-server` 挂载 `sops-age-key` secret。
- `External Secrets Operator` 从 Vault 下发运行时 Secret，Git 仓库只存引用。

## 访问控制
- Argo CD RBAC：`devops` 组拥有 admin 权限；站点团队仅能操作对应 `tenants/<store>` 应用。
- Git 仓库采用分支保护 + 必须通过 CI。

## 监控与审计
- Argo CD Application 与同步事件发送到 Grafana Loki。
- 所有 YAML 改动配合 `git tag release-<date>` 便于追溯。
