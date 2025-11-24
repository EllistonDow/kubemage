# Phase 4：Magento 多站部署指南

## 目标
1. 通过 Helm Chart（`charts/magento`）在 Kubernetes 上部署 Magento 2.4.8。
2. 每个站点独立 Namespace + Helm release，实现配置、资源、密钥隔离。
3. 将 Cron、队列消费者、Web、PHP-FPM、Varnish、Ingress、KEDA/HPA 等组件一体化管理。
4. 接入对象存储、CDN、ESO/Vault Secrets，完成端到端上线流程。

## 前提
- Phase 3 的依赖服务已就绪（Percona、OpenSearch、RabbitMQ、Valkey、Edge 控制器）。
- 镜像流水线（`docs/edge-build.md`）可产出最新 Magento Web/PHP/Cron 镜像。
- DNS/CDN（例如 Cloudflare）可配置到 MetalLB/Nginx Ingress 的公网 IP。
- 代码目录采用 `app/sites/<store>` 结构；在本地或 CI 中需要进入对应站点目录（如 `app/sites/demo`）执行 Composer/Magento 命令。

## 步骤
1. **命名空间与策略**
   - 为每个站点创建 Namespace（示例在 `cluster/phase4/namespaces/<store>.yaml`）。
   - 应用 `ResourceQuota`, `LimitRange`, `NetworkPolicy`, `PodSecurity` 规则。
2. **Secrets/Config**
   - 使用 ESO 拉取数据库、缓存、消息队列、S3 凭证；写入 `platform-secrets` 或站点 Namespace。
   - 媒体 bucket/Cloudflare API 写入 Secret。
3. **Helm 部署**
   - 根据 `charts/magento/values-store-example.yaml` 创建各站点 values。
   - `helm upgrade --install <store> charts/magento -n <namespace> -f values-store-example.yaml`。
4. **Ingress & CDN**
   - 在 Cloudflare/OVH DNS 将 `store.example.com` 指向 MetalLB LB IP。
   - 配置 Cloudflare Page Rules/缓存策略，使静态内容走 CDN，动态请求回源 Ingress。
5. **后置任务**
   - 运行 `bin/magento setup:upgrade`, `indexer:reindex`、`cache:flush`（通过 Job 或手动）。
   - 验证支付、邮件、搜索、消息队列消费。
   - 设置 `HPA/KEDA` 阈值，执行压力测试。

## 交付物
- `cluster/phase4/namespaces/*.yaml`: Namespace + Policy 定义。
- `charts/magento`: Helm chart（web/php/varnish/cron/consumers/HPA/Ingress）。
- `values-store-*.yaml`: 每站点配置示例。
- Runbook：`docs/runbooks/magento-deploy.md`（上线/回滚）。

## 验证清单
- Pod readiness 探针通过、`kubectl get pods -n <store>` 全部 Running。
- Web 访问 200、Varnish HIT 率 >70%（上线后）。
- Cron/消费者无 CrashLoop，RabbitMQ 队列稳定。
- 媒体读写测试（上传新媒体 -> S3 同步 -> CDN 刷新）。

完成 Phase 4 后可进入 Phase 5（运维、扩容、第二台裸机、Longhorn/Ceph、灾备演练）。
