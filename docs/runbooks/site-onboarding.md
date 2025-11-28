# 新站点上架流程（单站 Namespace）

> 目标：把一套新的 Magento 代码迁移到当前 K8s 集群，复用已有 Web/PHP/Cron/Pagespeed/Varnish 模板，并确保数据/密钥/镜像/监控都齐全。

## 1. 预检
- **代码目录**：复制 `app/sites/demo` 为 `app/sites/<site>`，替换 `app/etc/config.php` 中的域名、媒体配置等；删除 `var/`、`generated/`、`pub/static/`、`pub/media` 缓存。
- **数据库/媒资**：准备最新 SQL 与 `pub/media` 备份，建议导入后立即执行 `bin/magento setup:upgrade` 与 `remote-storage:sync`。
- **Secrets**：按照 `gitops/tenants/demo/secrets.enc.yaml` 模板填好 Access Key、数据库口令等，使用 `sops` 加密保存到 `gitops/tenants/<site>/secrets.enc.yaml`。

## 2. 构建镜像
```bash
SITE_PATH=app/sites/<site>
REGISTRY=ghcr.io/ellistondow

# Web + ngx_pagespeed + ModSecurity
SITE_PATH="$SITE_PATH" docker build -f Dockerfile.web -t $REGISTRY/kubemage-web:<site>-0.1.x .

# PHP-FPM
SITE_PATH="$SITE_PATH" docker build -f Dockerfile.php -t $REGISTRY/kubemage-php:<site>-0.1.x .

# Cron 镜像
SITE_PATH="$SITE_PATH" docker build -f Dockerfile.cron -t $REGISTRY/kubemage-cron:<site>-0.1.x .

docker push $REGISTRY/kubemage-{web,php,cron}:<site>-0.1.x
```
如需离线导入，可执行 `docker save | sudo ctr -n k8s.io images import -`。

## 3. GitOps 配置
1. 在 `gitops/tenants/<site>/` 下创建：
   - `namespace.yaml`（Namespace + 资源限额）。
   - `kustomization.yaml`（引用 namespace/application/secrets）。
   - `values-<site>.yaml`（Helm values，参考 demo/bdgy）。
2. 主要字段：
   - `image.web/php/cron.tag` 改为 `<site>-0.1.x`。
   - `env.baseUrl`、Redis/RabbitMQ/MySQL host。
   - `remoteStorage` bucket/prefix。
   - `web.pagespeed.enabled` & `varnish.enabled` 根据需求开关。
   - `secrets.create: false`、`secrets.name: <site>-magento-secrets`。
3. Git 提交后运行 `argocd app sync <site>`（或等待自动同步）。

## 4. 初始化站点
1. 导入数据库：`kubectl exec -n <ns> statefulset/percona-pxc -- mysql < dump.sql`。
2. 上传媒资到 MinIO：
   ```bash
   mc alias set kubemage http://minio.object-storage.svc.cluster.local:9000 <AK> <SK>
   mc mirror ./pub/media kubemage/<bucket>/media
   ```
3. 执行 `scripts/magento-builder.sh <ns> <release> ghcr.io/ellistondow/kubemage-php:<site>-0.1.x`，生成 `generated/`、`var/di/`、`pub/static/`。
4. `scripts/magento-keep-calm.sh <ns> <release>`：开启维护模式、`setup:upgrade`、索引与缓存刷新。

## 5. 验证 checklist
- `kubectl -n <ns> get pods -l app=<release>-magento-web` → 2/2 Running，`curl -I` 有 `X-Page-Speed`。
- `kubectl -n <ns> get deploy <release>-magento-php -o jsonpath='{.spec.template.spec.containers[0].image}'` 指向新 tag。
- `kubectl -n <ns> get secret <release>-magento-secrets -o yaml | sops --decrypt`（可选）确认键值完整。
- 访问站点前后台、下单流程、Cron/消费者日志没有报错。
- Grafana 中 Varnish/Nginx/Pagespeed/MinIO 指标全部绿色。

> 若需批量迁站，可把步骤 2-4 封装进自定义脚本或 CI，只要最终 artifacts 仍由 GitOps 管理即可。
