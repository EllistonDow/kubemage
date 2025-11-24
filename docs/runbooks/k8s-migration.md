# Magento 多站点 K8s 迁移规划

## 目标

1. 摆脱 docker-compose，所有站点与共享依赖统一运行在 Kubernetes。
2. 复用已有 Helm Chart / Operator CR，实现数据库、搜索、消息、缓存的集中治理（备份、监控、扩容）。
3. 通过 GitOps（Argo CD）发布，做到“改配置→自动部署”，并配套监控/告警/备份。

## 总体架构

- **命名空间划分**
  - `databases`：Percona Operator + PXC。
  - `search`：OpenSearch Operator + Dashboards。
  - `messaging`：RabbitMQ Cluster。
  - `cache`：Valkey（Bitnami Helm）。
  - `edge`：Ingress Controller / ModSecurity / Varnish（后续可扩展 Gateway API）。
  - `sites/<site>`：每个 Magento 站点独立 namespace（demo、bdgy、…）。
- **共享依赖**：Percona/OpenSearch/RabbitMQ/Valkey 通过 Operator 管理，S3 备份，Prometheus 采集指标。
- **站点栈**：Helm Chart `charts/magento` 部署 web/php/cron/consumers/varnish + Ingress，依赖上面共享服务。
- **GitOps**：`gitops/clusters/kubemage-prod` 引用 infra + platform + tenants；Secrets 用 SOPS 管理。

## 阶段划分

| 阶段 | 内容 | 交付物 |
| --- | --- | --- |
| Phase 0 | 工具安装、kubeconfig 就绪、registry/S3/StorageClass 确认 | CLI、凭证、设计评审 |
| Phase 1 | 部署底座（Cilium、MetalLB、OpenEBS/Longhorn、cert-manager） | `gitops/infra/*` 同步完成 |
| Phase 2 | GitOps 基座（Argo CD、Prometheus、Gatekeeper）上线 | `gitops/platform/*` 运行，提供监控/策略 |
| Phase 3 | 共享依赖 Operator + CR 部署，并进行数据回填 | `cluster/phase3/*` (Percona/OpenSearch/RabbitMQ/Valkey/Edge) |
| Phase 4 | 站点 Helm overlay（demo/bdgy…），构建镜像并首站点接入 Ingress | `gitops/tenants/<site>` 生效，域名解析切到 K8s |
| Phase 5 | 其它站点批量迁移、自动化备份/监控策略固化 | Runbook、SLO、演示验证 |

## 资源需求

- **计算**：建议 3+ 节点（每节点 ≥16 vCPU / 64 GiB），保证共享依赖可分散部署；站点根据负载扩容。
- **存储**：
  - PXC：至少 500 GiB 快速块存（`fast-local-zfs` 或同级别）。
  - OpenSearch：≥1 TiB（可扩展）。
  - Valkey/RabbitMQ：100 GiB 以内即可。
  - 站点媒体：S3（已有 `kubemage-media` 桶）或 RWX PVC（NFS/Longhorn）。
- **网络**：MetalLB 提供外部 LB，或使用云负载均衡；Ingress 证书由 cert-manager/Let’s Encrypt 签发。
- **对象存储**：S3 兼容桶（OVH、AWS 等），用于数据库/搜索备份。

## 集群初始化（当前进度）

单节点控制平面已在 `ns5007383` 上完成，关键步骤：

1. Disable swap：`sudo swapoff -a` 并在 `/etc/fstab` 注释掉 swap 分区（kubelet 要求）。
2. 安装 containerd + 配置 `SystemdCgroup=true`；加载 `overlay`/`br_netfilter`、设置 `net.ipv4.ip_forward=1` 等 sysctl。
3. 安装 `kubeadm/kubelet/kubectl` v1.31，执行 `sudo kubeadm init --pod-network-cidr=10.244.0.0/16`。
4. 创建 `$HOME/.kube/config`，部署 Calico v3.27.3：`kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml`。
5. 去除控制平面污点（单节点共担）：`kubectl taint nodes --all node-role.kubernetes.io/control-plane-`。
6. 安装 Helm 3：`curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`。

> 当前 `kubectl get nodes -o wide` 显示 `ns5007383` 为 `Ready`，可以直接调度业务 Pod，后续若新增节点，执行 `kubeadm token create --print-join-command` 获取 join 指令。

## 平台基座（GitOps/监控）

| 组件 | 命名空间 | 操作 | 备注 |
| --- | --- | --- | --- |
| Argo CD v2.11.4 | `argocd` | `kubectl create ns argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.4/manifests/install.yaml` | 初始密码：`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`；暂未配置外网入口，可用 `kubectl -n argocd port-forward svc/argocd-server 8080:443`. |
| kube-prometheus-stack | `monitoring` | `helm repo add prometheus-community ... && helm install kube-prom prometheus-community/kube-prometheus-stack -n monitoring --set grafana.enabled=false` | 仅启 Prometheus/Alertmanager/Node Exporter；如需 Grafana，将 `grafana.enabled` 设为 true，再设置 ingress/creds。 |

> GitOps Application：由于远端仓库还未合入最新 `kustomization.yaml` 调整，目前 Argo CD 尚未指向本仓库。待推送后，使用 `argocd app create kubemage ... --path gitops/clusters/kubemage-prod` 即可同步 platform/tenants。`argocd-cm` 已设置 `kustomize.buildOptions=--load-restrictor LoadRestrictionsNone`，方便引用跨目录资源。

## 本地存储类

单节点阶段安装了 `local-path-provisioner` 作为默认 StorageClass：

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

所有 StatefulSet (Percona/OpenSearch/RabbitMQ/Valkey) 的 PVC 都指定 `storageClassName: local-path`，后续可替换成 Ceph/Longhorn 等。

## 共享依赖（K8s 版）

位于 `cluster/phase4/shared/`，当前部署方式：

| 组件 | Namespace | 文件 | 说明 |
| --- | --- | --- | --- |
| Percona Server 8.4 | `databases` | `cluster/phase4/shared/percona.yaml` | StatefulSet + PVC(100Gi)，root 密码存于 `percona-root` Secret。Service `percona.databases.svc` 供站点连接。|
| OpenSearch 2.19 | `search` | `cluster/phase4/shared/opensearch.yaml` | StatefulSet 单节点，`plugins.security` 禁用、`OPENSEARCH_INITIAL_ADMIN_PASSWORD=OsAdm#2025Strong!`。HTTP Service `opensearch-http.search.svc:9210`.|
| RabbitMQ 4.1 | `messaging` | `cluster/phase4/shared/rabbitmq.yaml` | StatefulSet + Secret（`magento/magentoPass`），Service 暴露 AMQP + 15672。|
| Valkey 8 | `cache` | `cluster/phase4/shared/valkey.yaml` | StatefulSet 20Gi，Service `valkey.cache.svc:6379`。|

部署命令：

```bash
kubectl create ns databases search messaging cache edge
kubectl apply -f cluster/phase4/shared/percona.yaml
kubectl apply -f cluster/phase4/shared/opensearch.yaml
kubectl apply -f cluster/phase4/shared/rabbitmq.yaml
kubectl apply -f cluster/phase4/shared/valkey.yaml
```

> 状态验证：`kubectl get pods -n databases|search|messaging|cache` 均为 Running，OpenSearch 初次需要设置 `OPENSEARCH_INITIAL_ADMIN_PASSWORD`，日志提示“Password is similar”时需重新设置更复杂的密码。

## 站点 values 模板

`gitops/tenants/{demo,bdgy}/values-*.yaml` 已写入默认主机/共享服务地址、Redis DB 编号、Varnish Secret 名称以及镜像仓库占位符。上传 GitOps 前务必：

1. 替换 `image.*.repository/tag` 为真实镜像；
2. 将 `secrets.*` 用 SOPS 加密（现为 `ENC[TODO]` 占位）；
3. 创建 `demo-varnish-vcl` / `bdgy-varnish-vcl` Secret，存放 `default.vcl`；
4. 若需要 OpenSearch 基本认证，可在 values 增加 `openSearchUser/openSearchPassword`。

后续需要把 `gitops/clusters/kubemage-prod/kustomization.yaml` 指向的 repo（本地 `gitops/` 目录）纳入 Argo CD，通过 `argocd app create` 或 UI 添加来源，即可让 infra/platform/tenant overlay 自动部署。

## 需要完成的主要任务

1. **工具链/配置**
   - 安装 `kubectl`、`helm`、`argocd` CLI。
   - 准备 kubeconfig（指定目标集群）。
   - 确认 Docker registry（推送 web/php/cron 镜像）。
2. **共享依赖**
   - 调整 `cluster/phase3` 中 StorageClass、S3 参数，提交 GitOps。
   - 使用 `artifacts/shared-backups` 中最新 SQL/快照导入新环境。
3. **站点 Helm overlay**
   - 在 `gitops/tenants/` 下创建 `demo/`、`bdgy/` 目录，复用 store1 模板。
   - 编写 `values-demo.yaml.enc`、`values-bdgy.yaml.enc`（镜像 tag、域名、DB/Redis、RabbitMQ vhost、OpenSearch prefix、Varnish secret 等）。
   - 构建/推送对应镜像（web/php/cron）。
4. **GitOps 应用**
   - 更新 `gitops/clusters/kubemage-prod/kustomization.yaml`，加入新 tenants。
   - 在 Argo CD 创建 Application 指向该 kustomization，确保 infra/platform/tenants 同步成功。
5. **数据切换**
   - 在 K8s Percona 中导入数据库，执行 `bin/magento` 升级/编译。
   - 验证站点 Ingress，切换 `*.k8s.bdgyoo.com` DNS。
   - 启用 Prometheus / Alertmanager 告警（包括 Valkey/RabbitMQ 指标、共享层备份状态）。

## 开工前清单

- [ ] kubeconfig / 节点资源确认
- [ ] S3 凭证 / StorageClass 复核
- [ ] Registry 地址 & 凭证设置
- [ ] 站点密钥（repo.magento.com key、RabbitMQ/Redis/DB 密码）整理并通过 SOPS 加密
- [ ] 备份：执行 `scripts/shared-backup.sh`，冻结导入点

准备就绪，即可按照 Phase 顺序提交 GitOps 变更并在集群上开始部署。
