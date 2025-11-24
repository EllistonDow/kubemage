# Magento 2.4.8 K8S 详细实施计划

> 时间基线假设：M0 = 启动日起第一周结束；具体日期可在执行前根据人力重新估算。

## Phase 1：集群引导（预估 1–1.5 周）
- **1.1 宿主预检**：执行 Phase 0 checklist，确认 ZFS/网络/虚拟化状态。
- **1.2 节点拓扑**：
  - 单机阶段：control-plane×3（VM 或 `kube-vip` 虚拟 IP）+ worker×1。
  - 设定节点标签：`node-role.kubernetes.io/control-plane`、`node-role.kubernetes.io/infra`。
- **1.3 kubeadm**：
  - 生成 `ClusterConfiguration`（Kubernetes v1.30.x、podCIDR: 10.42.0.0/16、serviceCIDR: 10.43.0.0/16）。
  - `kubeadm init --config cluster.yaml`，保存 `/etc/kubernetes/admin.conf` 到 Vault。
  - 加入其余 control-plane / worker 节点。
- **1.4 核心插件**：
  - 安装 Cilium（启用 Hubble Relay/UI、BGP disabled、kube-proxy replacement）。
  - MetalLB：配置 L2Advertisement，使用 OVH Failover IP 段。
  - metrics-server、kube-state-metrics、node-exporter。
  - OpenEBS ZFS-LocalPV（`StorageClass=fast-local-zfs`）。
- **1.5 验证**：执行 `sonobuoy run --mode=quick`，保留报告。

## Phase 2：平台基础服务（预估 1.5 周）
- **2.1 GitOps**：
  - Git 仓库三层结构：`infra/`（cluster addons）、`platform/`（共享服务）、`tenants/<store>/`。
  - 部署 Argo CD，配置 app-of-apps 模式，接入 SOPS 插件。
- **2.2 安全基线**：
  - OPA Gatekeeper：策略包含 PodSecurity、只读 rootfs、label 规范。
  - Kyverno（可选）：生成探针/label/annotation。
  - External Secrets Operator + Vault/KMS。
- **2.3 可观测**：
  - kube-prometheus-stack：启用 Thanos sidecar，远期做对象存储归档。
  - Loki+Tempo+Promtail，统一日志/链路。
  - Alertmanager 通知（PagerDuty 或 OVH SMS）。
- **2.4 自动化**：
  - KEDA（RabbitMQ scaler、cron scaler）。
  - kured（结合同步维护窗口 label）。
  - Velero（S3 bucket，含 restic）。

## Phase 3：依赖服务（预估 2 周）
- **3.1 数据库**：
  - Percona Operator 部署 PXC，单主+async replica placeholder。
  - 启用 PITR（binlog -> S3），每日备份作业。
- **3.2 OpenSearch**：
  - Cluster：`1 master + 1 data_hot`（同 Pod），设置 `node.attr.temp=hot` 以便未来 warm-tier。
  - SLM -> S3，ILM policy 针对 Magento logs/search。
- **3.3 RabbitMQ**：
  - 单节点集群 + quorum queues，预设 `policies` 和 `users`。
  - Prometheus + Grafana dashboard。
- **3.4 Valkey**：
  - Helm Chart（主/从 + Sentinel），持久化 `appendonly yes`。
  - KEDA Source 监听 Valkey 指标用于消费者扩缩。
- **3.5 Edge 组件**：
  - Varnish Operator/Helm：自定义 VCL、PROXY 协议支持。
  - Nginx Ingress Controller（modsecurity + OWASP CRS）。
  - 镜像流水线：GitHub Actions/GitLab Runner 运行 composer build、`setup:di:compile`、`setup:static-content:deploy`，生成 `magento-web` 与 `magento-php-fpm` 镜像。

## Phase 4：Magento 多站（预估 2 周）
- **4.1 Helm Chart**：
  - Chart 结构：`web`, `fpm`, `varnish`, `cron`, `consumer`, `configmap`, `secret`, `hpa`。
  - `values-store.yaml` 控制 base URL、主题、队列并发、媒体 bucket。
- **4.2 Namespace 策略**：
  - 每站点 Namespace 自带 `ResourceQuota`, `LimitRange`, `NetworkPolicy`。
  - ServiceAccount + RBAC 限制（仅能访问本 Namespace）。
- **4.3 数据接入**：
  - 数据库 schema 初始化、媒体导入脚本、Env Secret（Vault 注入）。
  - 对象存储同步：magento media sync job + CDN purge。
- **4.4 验证**：
  - 功能测试（checkout、支付回调）、性能压测（JMeter + Locust）。
  - 按站点生成 Runbook（部署、扩缩、回滚）。

## Phase 5：运维/扩容（并行 & 持续）
- **5.1 备份/恢复演练**：季度演练 MySQL/OpenSearch/Valkey/RabbitMQ/Velero。
- **5.2 升级策略**：Kubernetes 次版本节奏（N-1），Magento 安全补丁流程。
- **5.3 第二台裸机**：
  - 复用 Phase 0/1 流程，加入 vRack。
  - etcd/控制面平衡，StatefulSet 副本扩展，启用 PodAntiAffinity。
  - 引入 Longhorn 或 Rook-Ceph，迁移 PVC。
- **5.4 SRE Runbook**：值班手册、告警分级、事故通报模板。

## 交付物索引
| 文件/资产 | 描述 |
| --- | --- |
| `cluster/cluster.yaml` | kubeadm 配置，含 API server/VIP 等细节 |
| `infra/` | Cilium、MetalLB、OpenEBS、monitoring、logging manifests |
| `platform/` | Operator、GitOps、安全策略、CI/CD config |
| `tenants/<store>/values.yaml` | 每个站点部署参数 |
| `runbooks/` | 备份、扩容、升级、事故处理文档 |

## 风险与应对
1. **单机阶段硬件故障**：依赖 S3 冷备 + 外部对象存储；在 Phase 5 前需准备热备机。
2. **Operator 版本不兼容**：在独立 `staging` Namespace 做 canary；启用 `helmfile`/`kustomize` 锁定版本。
3. **存储 IO 瓶颈**：监控 NVMe 延迟，必要时在宿主上开启多队列与 CPU 亲和；提前规划二期分布式存储。
4. **人力/流程风险**：所有脚本写入仓库，CI 自动 lint/validate（`kubectl diff`、`kubeconform`），减少人工失误。
