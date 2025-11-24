# Magento 2.4.8 K8S 方案蓝图

## 纲领
1. **平台一致性优先**：以 Ubuntu 24.04 LTS 为唯一宿主系统基线，使用 kubeadm+containerd 架构，并通过 GitOps（Argo CD）管理所有声明式资源，确保平台和站点在同一模版下演进。
2. **Operator + StatefulSet 驱动的可靠依赖**：Percona MySQL、OpenSearch、RabbitMQ、Valkey 等全部采用官方或主流 Operator，利用 StatefulSet+PVC+PDB 达成可重调度能力，并为第二台裸金属预留副本策略。
3. **网络安全一体化**：Cilium 负责 CNI/NetworkPolicy/L7 可视化，MetalLB 提供 LB IP，Ingress 端启用 Nginx+ModSecurity，WAF/速率限制与 Cilium Policy 联动构建零信任网络。
4. **存储与备份双轨**：现阶段使用 ZFS RAID1 + OpenEBS ZFS-LocalPV 提供本地存储；同步构建对象存储备份链路（S3 兼容），为未来接入 Rook-Ceph/Longhorn 打基础。
5. **可观测与自动化优先**：Prometheus/Loki/Tempo + Grafana 做统一观测，KEDA/HPA 自适应扩缩，kured/KubeArmor/OPA 保障安全与稳定；任何手工步骤都通过脚本/文档固化。
6. **多站隔离与弹性**：每个站点一个 Namespace + Helm release，配置/密钥使用 SOPS 加密；Cron、消费者、Web、FPM 拆分 Deployment，借助 RabbitMQ/KEDA 进行站点级弹性扩缩。

## 详细计划
| 阶段 | 目标 | 关键任务 | 产出 |
| --- | --- | --- | --- |
| Phase 0：准备与假设 | 明确资源与边界条件 | \- 盘点现有硬件、网络（OVH vRack、公网 IP、带宽）
\- 决定是否以轻量虚拟化（KVM/Proxmox）拆分控制面
\- 编制 Ubuntu 24.04 裸机加固 checklist（内核 pin、cloud-init、DNSStubListener、AppArmor） | \- 资源清单
\- 宿主机初始化脚本
\- 安装/加固文档 |
| Phase 1：集群引导 | 建立可扩展的 kubeadm 集群 | \- 创建 control-plane/worker 节点（单机多 VM 或直接 hostNetwork）
\- kubeadm init + join（启用 cgroup v2、containerd）
\- 安装 Cilium、MetalLB、metrics-server、Cluster Autoscaler（后续对接）
\- 配置 StorageClass（OpenEBS ZFS-LocalPV + snapshot class） | \- 已运行的 K8s 集群
\- Cilium/MetalLB/StorageClass 可用
\- 集群基线文档 |
| Phase 2：平台基础服务 | 准备 GitOps、安全、监控等公共能力 | \- 搭建 Argo CD + repo 结构（infra/platform/tenants）
\- 部署 Vault/External Secrets + SOPS 集成
\- Prometheus + Loki + Tempo + Grafana 套件（含 OVH Alert 通知）
\- 部署 OPA Gatekeeper/Kyverno、KubeArmor、kured
\- 配置 Harbor 或 OVH Registry 作为镜像源 | \- GitOps 仓库
\- 监控/日志栈
\- 安全策略/准入策略 |
| Phase 3：依赖服务落地 | 让 Magento 依赖栈可在 K8s 上运行 | \- Percona XtraDB Cluster Operator：单主模式 + binlog 备份 + S3
\- OpenSearch Operator：1 主分片 + snapshot repo
\- RabbitMQ Operator：单节点 + topology spread + Prometheus exporter
\- Valkey(Redis) 集群：主/从 + Sentinel
\- Varnish、Nginx、PHP-FPM 镜像 pipeline（Composer 2.8、PHP 8.3 模块） | \- StatefulSet/Helm values
\- 备份/恢复演练记录
\- 镜像构建流水线 |
| Phase 4：Magento 多站部署 | 交付首批站点并验证弹性 | \- 编写 Magento Helm Chart（或复用 upstream）并参数化 store
\- Namespace/ResourceQuota/LimitRange 设计
\- 建立 Cron/Consumer/KEDA 配置模板
\- 配置对象存储媒体同步、CDN/Cloudflare 接入
\- 实施 WAF/速率限制/Bot 规则 | \- 每站点部署说明
\- 运行中的 Magento Pod/Service
\- 媒体同步/发布流程文档 |
| Phase 5：运维与扩展 | 为第二台服务器和持续运维做准备 | \- 例行备份/恢复演练（MySQL、OpenSearch、Valkey、集群对象）
\- 性能基线与容量模型（QPS、索引大小、队列深度）
\- 第二台裸机上线流程（etcd 扩容、StorageClass 切换、PDB/anti-affinity 调整）
\- 灾备与升级 runbook（内核、K8s、Magento patch） | \- Runbook 套件
\- 容量/扩展报告
\- 二期上线脚本 |

## 里程碑 & 依赖
1. **M0（T+1 周）**：宿主 OS 加固 + kubeadm 集群初始化完成。
2. **M1（T+3 周）**：GitOps/监控/安全基座上线，依赖服务 Operator 部署成功。
3. **M2（T+5 周）**：首个 Magento 站点（Web+FPM+Varnish+Cron+Consumer）在集群稳定运行，通过功能与性能验证。
4. **M3（T+8 周）**：备份/恢复演练、容量测试完成，形成 SRE runbook，准备第二台服务器加入。

## 下一步
1. 根据 Phase 0 checklist 开始编写宿主机初始化脚本（cloud-init/netplan/AppArmor）。
2. 评估是否引入轻量虚拟化以拆分控制面；若需要，制定 VM 资源划分表。
3. 建立 GitOps 仓库骨架并接入 Argo CD，随后进入 Phase 1 具体实施。

## 仓库结构速览
- `app/sites/<site>`：每个站点一套完整的 Magento 代码（当前演示站位于 `app/sites/demo`）。后续引入新站点时，复制 `demo` 目录并在 CI/Helm 中指定对应的 `SITE`/镜像标签即可。
- `docker/`、`Dockerfile.*`：Web/PHP/Cron 镜像构建所用的配置与 Dockerfile，已经支持 `SITE_PATH` 构建参数。
- `infra/docker-compose.yml`：本地联调栈（Percona/OpenSearch/RabbitMQ/Valkey + Magento）默认挂载 `app/sites/<site>`。
- `docs/`：阶段指南、runbook、镜像/部署文档；`docs/image-build.md` 与 `docs/phase4-guide.md` 已说明多站目录结构。
