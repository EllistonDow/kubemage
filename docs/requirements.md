# OVH 单机硬件 & Magento 2.4.8 K8s 部署规划

## 1. 硬件概述
- **宿主机**：OVH 独立服务器 AMD EPYC 7302（16c/32t，3.0/3.3 GHz），128 GB ECC 内存，2 × 1.92 TB NVMe SSD（Soft RAID）。
- **扩展**：后续可再加入一台同配置；所有规划从单节点起步，确保第二台加入时无需推倒重来。

## 2. 宿主 OS 与基础设施
- **操作系统**：Ubuntu Server 24.04 LTS，启用 cgroup v2、AppArmor、chrony，按 `docs/phase-0-checklist.md` 加固。
- **虚拟化/容器**：kubeadm + containerd；启用 nerdctl/buildkit 便于本地镜像构建。
- **磁盘策略**：NVMe 做 ZFS RAID1，划分 system（200G）+ data pool；K8s 里配 OpenEBS ZFS-LocalPV 为默认 StorageClass，Phase5 时可平滑迁移 Longhorn/Rook。
- **网络**：双口启用 OVH vRack，主网段跑 Kubernetes/Ingress，MetalLB 负责对外 IP 池；WireGuard 打穿第二台主机。

## 3. Kubernetes 基座
| 组件 | 版本/策略 |
| --- | --- |
| kubeadm cluster | 3 control-plane taints 先保留，当前单机以 hostNetwork 节约资源；第二台加入后迁移 etcd/控制面 |
| CNI | Cilium (eBPF, Hubble, BGP)；NetworkPolicy + L7Policy 实现零信任 |
| Ingress | Nginx 1.28 + ModSecurity（OWASP CRS）；配合 Cilium API 网关模式 |
| LB | MetalLB L2 + BGP（与 Cilium 集成）|
| DNS/证书 | CoreDNS, ExternalDNS (Cloudflare), cert-manager + Let’s Encrypt DNS01 |
| 节点安全 | KubeArmor, Falco, OPA Gatekeeper/Kyverno, kured |
| 存储 | OpenEBS ZFS-LocalPV + Velero (S3) 快照；Phase5 切 Longhorn |
| GitOps | Argo CD 根目录按照 `gitops/README.md` (infra/platform/tenants) |
| Secrets | SOPS + age，密钥存放 `sops/`，流水线/Helm 统一解密 |

## 4. Magento Official Requirement 映射
| Requirement | 规划 | 备注 |
| --- | --- | --- |
| Composer 2.8 | CI 中 `shivammathur/setup-php` 安装 Composer 2.8；本地镜像 pipeline 也锁定 2.8 (`Dockerfile.php`) |
| PHP 8.3 | Dockerfile.php/cron 基于 Ubuntu 24.04 + php8.3 套件；镜像内运行 FPM & CLI |
| Nginx 1.28 + ModSecurity | Dockerfile.web 进一步升级到 nginx 1.28 + libmodsecurity；Ingress 使用 Nginx Controller + CRS |
| Varnish 7.6 | Phase3 计划部署 Varnish Deployment，前置 Redis/Valkey；自定义 VCL 由 ConfigMap 提供 |
| Valkey 8 | 使用 Bitnami/Valkey Operator 或 Redis Operator（Valkey 模式），主从 + Sentinel |
| RabbitMQ 4.1 | RabbitMQ Cluster Operator，单节点起步；KEDA 消费者自动缩放 |
| OpenSearch 2.19 | OpenSearch Operator，data+ingest 节点各 1；S3 snapshot + Curator 生命周期 |
| Percona 8.4 | Percona Operator for MySQL/PXC，单写多读；S3/XtraBackup 定期备份 |

## 5. 镜像与 CI/CD
- `.github/workflows/build-magento.yml`：composer install → `setup:di:compile` → `setup:static-content:deploy` → build/push web、php、cron 三种镜像。
- 镜像标签：`registry.ovh.net/kubemage/<component>:<git-sha>`；CI 完成后自动缓存 Buildx。
- 文档对齐：`docs/image-build.md` 描述本地构建/联调，`docs/edge-build.md` 记录 SBOM/签名。

## 6. 多站部署策略
1. **单代码多 Store**：沿用 `app/` 根目录代码，通过 Magento multi-store + Helm values 控制站点配置。
2. **多目录/多仓**：当前仓库已采用 `app/sites/<site>` 结构（演示站 `app/sites/demo`），Dockerfile 通过 `SITE_PATH` 构建参数选择站点目录，CI 用矩阵构建多站镜像；GitOps 为每个站点独立 namespace + chart values。
3. **Secrets & Config**：每站点 `gitops/tenants/<store>` 持有 values + 加密 secrets；`tenants/store1/values-store1.yaml.enc` 为示例。

## 7. Phase 执行摘要
- Phase0：`scripts/host-init.sh` 根据上面硬件配置初始化（bios、raid、netplan）。
- Phase1：kubeadm + Cilium + MetalLB + OpenEBS。
- Phase2：GitOps、监控、SOPS、安全 Operator。
- Phase3：部署 Percona、OpenSearch、RabbitMQ、Valkey、Varnish、Harbor/Registry。
- Phase4：镜像构建 → Helm 部署 Magento Web/FPM/Cron/Consumers；KEDA & HPA。
- Phase5：Longhorn + Velero，二号机并入，容量/灾备演练。

## 8. 下一步
1. 按本规划更新 `docs/phase3-guide.md` 和相关 Helm values 的默认版本号。
2. 在 `scripts/` 目录补充 OpenSearch/RabbitMQ/Valkey/Percona Operator 安装脚本或 Makefile 目标。
3. 准备本地安装依赖（MySQL、OpenSearch 等）以便执行 `php bin/magento setup:install` 并生成 `app/etc/env.php`。

## 9. 本地容器化依赖
为避免在宿主机反复安装不同版本，可通过 Docker Compose 在 `infra/docker-compose.yml` 启动 RabbitMQ 4.1、Valkey 8、Varnish 7.6：

```bash
cd /home/doge/kubemage
sudo docker-compose -f infra/docker-compose.yml up -d
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

- **RabbitMQ 4.1**：`amqp://magento:magentoPass@127.0.0.1:5672/`，管理界面 `http://127.0.0.1:15672`。
- **Valkey 8**：`redis://127.0.0.1:6379`，默认启用 AOF（`valkey/valkey:8`）。
- **Varnish 7.6**：监听 `127.0.0.1:6081`，后端指向宿主机 Nginx（`host.docker.internal:80`），`infra/varnish/default.vcl` 已包含 PURGE ACL 示例，可通过 `curl -I -H 'Host: magento.k8s.bdgyoo.com' http://127.0.0.1:6081` 验证。

容器 volume (`rabbitmq-data`, `valkey-data`) 持久化在 Docker 本地卷。后续迁移到 Kubernetes 时，可直接复用相同的连接字符串，并由 Phase3 Helm chart 切换为各自的 Operator（Percona XtraDB、RabbitMQ Cluster Operator、Valkey Operator、Varnish Deployment）。

## 10. Magento 配置对接容器依赖
- `app/etc/env.php` 已将 **Redis/Valkey** 用于所有缓存：`database 0` 负责默认缓存、`1` 负责 page cache、`2` 负责 session、`3` 负责分布式锁。命令行中可用 `redis-cli -n <db>` 验证键数量。
- `page_cache` 节点新增 `http_cache_hosts`，将 Varnish 7.6 (`127.0.0.1:6081`) 作为唯一前端；部署在 K8s 时仅需把地址替换为 Varnish Service 或外部 LB。
- `queue.amqp` 指向 Docker RabbitMQ (`amqp://magento:magentoPass@127.0.0.1:5672/`)；`bin/magento queue:consumers:list` / `queue:consumers:start` 会自动走该连接，管理台 `http://127.0.0.1:15672` 可观察消费堆积。
- Session 改为 Redis 模式，`php bin/magento cache:flush` 后无需清空 `var/session`。若需暂时回退文件会话，只需把 `session.save` 改回 `files` 并删除 `session.redis` 数组。
- 锁服务暂留 DB provider（Magento 2.4.8 CE 尚未内置 redis lock backend），待升级至支持的版本后再切 Redis；K8s 场景可通过 EtcdLock/DB Failover 保障互斥。

> 验证建议：在 `docker-compose` 服务运行的情况下执行 `bin/magento cache:clean && bin/magento queue:consumers:start async.operations.all --max-messages=100`；RabbitMQ 控制台应出现连接，Valkey `INFO keyspace` 能看到 DB0-DB3 均有命中。
