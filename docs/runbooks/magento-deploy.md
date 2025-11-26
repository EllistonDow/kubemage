# Magento 部署/回滚 Runbook

## 首次部署
1. **准备**：
   - 确认依赖命名空间与 Secrets（数据库、Valkey、RabbitMQ、S3）已就绪。
   - CI 构建最新镜像并推送 registry。
2. **创建 values**：复制 `charts/magento/values-store-example.yaml`，替换 baseUrl、bucket、镜像 tag 等。
3. **部署**：
```bash
helm upgrade --install store1 charts/magento -n store1 -f values-store1.yaml
```
4. **后置脚本**：
```bash
kubectl exec -n store1 deploy/store1-magento-php -- \
  php bin/magento setup:upgrade && \
  php bin/magento setup:static-content:deploy -f en_US zh_CN && \
  php bin/magento cache:flush
```
5. **验证**：
   - `kubectl get pods -n store1`
   - Web 打开首页，操作购物车和结算。
   - RabbitMQ 队列消费正常，Elasticsearch/OpenSearch 搜索可用。

## 远程存储（MinIO）
1. **凭据下发**：在 `values-*.yaml` 中设置 `remoteStorage.*` 与 `secrets.remoteStorage*`，`helm template` 会把 `REMOTE_STORAGE_*` 环境变量注入 PHP/Cron/Builder Pod。
2. **同步历史媒体**（每个站点都要执行一次）：
   ```bash
   kubectl exec -n demo deploy/demo-magento-php -- php bin/magento remote-storage:sync
   kubectl exec -n bdgy deploy/bdgy-magento-php -- php bin/magento remote-storage:sync
   ```
3. **验证**：
   ```bash
   kubectl exec -n demo deploy/demo-magento-php -- php -r 'var_export((include "app/etc/env.php")['"'remote_storage'"']);'
   # 期望 driver=aws-s3，bucket=demo-media，credentials=demoMediaUser 等
   ```
4. `pub/media` 改为只读缓存后，所有新上传的图片会直接写入 MinIO，配合 restic/Velero 即可做多站点共享备份。

## Varnish & 缓存策略
1. **集群内 Ban 白名单**：`values.yaml`/`values-<site>.yaml` 中的 `varnish.purgeCIDRs`（默认 `10.0.0.0/8`）会写入 `acl purge`。这样 PHP/Cron/Builder Pod 发起的 `PURGE` 就不会再因为源 IP 属于 Pod 网段而被 405 拒绝。
2. **手工 Ban 示例**：
   ```bash
   # 方式 A：在 PHP Pod 直接调用 Varnish Service
   kubectl exec -n bdgy deploy/bdgy-magento-php -- \
     curl -X PURGE -H 'Host: bdgy.k8s.bdgyoo.com' \
          -H 'X-Magento-Tags-Pattern: .*' \
          http://varnish:6081/

   # 方式 B：登录 Varnish Pod，针对域名 Ban
   kubectl exec -n bdgy -it deploy/bdgy-magento-varnish -- \
     varnishadm ban 'req.http.host == "bdgy.k8s.bdgyoo.com"'
   ```
3. **404 不再缓存**：`charts/magento/files/varnish/default.vcl` 把 404/5xx 响应标记为 `uncacheable`。即便站点在初始化过程中短暂抛出 `errors/2025`，Varnish 也不会把该页面缓存几小时；若仍看到旧页面，执行上面的 Ban 命令或 `php bin/magento cache:flush full_page` 即可。

## Argo CD 集成
1. **应用定义**：每个站点都在 `gitops/tenants/<site>/application.yaml` 里声明了 Argo CD `Application`（Helm 类型，路径 `charts/magento`），`valueFiles` 直接引用同目录下的 `values-<site>.yaml`。`syncPolicy` 默认开启 `selfHeal` 与 `CreateNamespace=true`，避免手工 `helm upgrade`。
2. **基线资源**：`gitops/tenants/<site>/namespace.yaml` 保留 Namespace/Quota/LimitRange/NetworkPolicy，仍由 `kubemage` 根应用统一下发，防止 Argo Application 删除 PVC/命名空间。
3. **引导流程**：
   ```bash
   kubectl apply -f gitops/tenants/demo/application.yaml
   kubectl apply -f gitops/tenants/bdgy/application.yaml
   # 根应用
   kubectl apply -f gitops/platform/gitops/kubemage.yaml
   ```
   之后可在 Argo UI 中看到 `demo`、`bdgy` 两个 Helm Release，点击 Sync 就会执行 `helm upgrade`。
4. **注意事项**：自动同步默认不 prune（防止 PVC 被误删），如果需要在 Git 中删除资源，先手动确认对应数据卷已备份，再暂时允许 `prune`。

## 队列消费者
1. **默认覆盖范围**：`gitops/tenants/<site>/values-<site>.yaml` 的 `consumers.list` 现在预置了 `async.operations.all` 以及 `product_action_attribute.{update,website.update}`，对应 Deployment 会自动挂载 `generated/`、`var/di/` 卷并跟随站点镜像滚动更新。
2. **添加新消费者**：按下列格式扩展列表即可：
   ```yaml
   consumers:
     enabled: true
     list:
       - name: media-gallery
         queue: media.gallery.synchronization
         maxMessages: 200
   ```
   Helm 会生成 `deploy/<release>-magento-consumer-media-gallery`，无需单独写 manifests。
3. **排障**：若 RabbitMQ 中 `messages_ready` 长时间 > 0，可先运行 `rabbitmqctl list_queues -p /<site> name messages_ready consumers` 确认队列名，再对照 `values-<site>.yaml` 是否已有对应 Deployment；必要时使用 `kubectl logs deploy/<release>-magento-consumer-...` 检查连接/权限。
4. **KEDA 后续**：Chart 已内建 `keda.rabbitmq` 节点，可在站点 values 里设置 `keda.rabbitmq.enabled=true`、`queueName` 等参数，让 `async.operations.all` 随 backlog 自动扩缩。

## 生成物刷新（Composer + PVC）
1. **Composer 排除 generated**：确保 `composer.json` 的 `autoload.exclude-from-classmap` 含 `generated/code/*`，避免 `composer dump` 把已删除的 Proxy 重新写入 classmap。
2. **重新生成 autoload**（以 demo 为例）：
   ```bash
   cd app/sites/demo
   docker run --rm -v "$PWD":/var/www/html -w /var/www/html \
     -e COMPOSER_ALLOW_SUPERUSER=1 composer:2.8 \
     dump-autoload --no-dev --optimize
   ```
   bdgy 站点同理。操作后将 `composer.json` 与 `vendor/composer/*` 一并提交。
3. **刷新 PVC 生成物**：
   ```bash
   MAGENTO_BUILDER_COMPILE=1 MAGENTO_BUILD_STATIC=1 \
   MAGENTO_STATIC_LOCALES="en_US zh_Hans_CN" \
   ./scripts/magento-builder.sh demo demo ghcr.io/ellistondow/kubemage-php:demo-0.1.2
   ```
   根据站点替换 namespace/release/image。Job 会先运行 `setup:upgrade` → `setup:di:compile` → `setup:static-content:deploy`，再把 `generated/`、`var/di/`、`pub/static/` 回写到 PVC（`*-generated`、`*-vardi`、`*-pubstatic`）。
4. **验证**：
   ```bash
   kubectl exec -n demo deploy/demo-magento-php -- ls generated | head
   kubectl exec -n demo deploy/demo-magento-php -- php bin/magento list | head
   ```
   若 CLI 能正常运行且前台资源不 404，即可重新开启 Cron/消费者。

## 一键巡检（keep calm）
在 Kubernetes 环境中执行整套「升级-清缓存-重建索引」命令，可直接使用 `scripts/magento-keep-calm.sh`：

```bash
./scripts/magento-keep-calm.sh demo demo
./scripts/magento-keep-calm.sh bdgy bdgy --context kubemage-prod
```

脚本流程：maintenance:enable → app:config:import → setup:upgrade → cache:flush/cache:clean → indexer:reindex → queue:consumers:restart → maintenance:disable。若需附加 `kubectl` 参数（context、token 等）直接跟在 release 名称后。

## 回滚
1. 找到上一版本 Helm release：`helm history store1 -n store1`。
2. `helm rollback store1 <REVISION>`。
3. 如果数据库 schema 变更不兼容，使用 Percona PITR 恢复相应时间点。
4. 回滚完成后运行 `php bin/magento cache:flush`。

## 常见问题
- **首页被 `errors/2025` 404 缓存**：多出现在 Varnish 先返回 404、站点随后才完成 `setup:upgrade` 的窗口期。升级到最新版 Chart 并执行上面的 Ban 命令，可以即时抹掉旧对象；同样可以 `php bin/magento cache:flush full_page` 触发 Magento 自己的 BAN。
- **/static/ 404 或后台无样式**：Chart 默认会创建 `*-pubstatic` PVC，并把 PHP/Web Pod 的 `/var/www/html/pub/static` 挂到该卷；若手动改过 Deployment 导致未挂载，或 Builder/keep-calm 没把静态文件同步到 PVC，就会出现 CSS/JS 404。解决办法：恢复 Helm 模板的 `volumeMounts`，然后运行 `scripts/magento-builder.sh <ns> <release> <php-image>`（记得设置 `MAGENTO_BUILD_STATIC=1`）让 `pub/static` 写入 PVC，最后重新同步 ArgoCD。
- **部署卡在 Pending**：检查 Namespace ResourceQuota、PVC 是否绑定、Cilium NetworkPolicy。
- **健康探针失败**：审查 FPM/Nginx 日志，确认 ENV/Secrets 是否正确。
- **队列积压**：增加 Consumers、副本或调高 RabbitMQ limits。

## 发布前检查表
- [ ] 镜像扫描通过（Trivy）。
- [ ] Helm values 经 `helm template` 验证。
- [ ] GitOps PR 已审核。
- [ ] 运行 `kubectl diff`（如果 GitOps 外部署）。
- [ ] CDN/DNS 已指向新环境。
