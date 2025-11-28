# 镜像构建与本地测试

## 目录结构
- `app/sites/<site>`：每个站点的 Magento 代码（示例站点为 `app/sites/demo`），CI/本地构建时需在该目录下执行 Composer 与 Magento 命令。
- `Dockerfile.web`, `Dockerfile.php`, `Dockerfile.cron`：分别用于 Nginx、PHP-FPM、Cron 镜像。
- `docker/`：Nginx、PHP、Cron 配置。

## 本地构建
```bash
REGISTRY=registry.ovh.net/kubemage
podman build -f Dockerfile.php -t $REGISTRY/magento-php-fpm:dev .
podman build -f Dockerfile.web -t $REGISTRY/magento-web:dev .
podman build -f Dockerfile.cron -t $REGISTRY/magento-cron:dev .
```

### 构建优化
- 根目录新增 `.dockerignore`，默认忽略 `artifacts/`、`docs/`、`charts/` 等与镜像无关的内容，以及 Magento 的 `var/cache`、`pub/static/*`、`generated/*`、`pub/media` 缓存目录，显著降低 BuildKit 上下文大小（从 ~4GB 降到 < 1GB）。
- `Dockerfile.php` 在复制完站点代码后会重新创建 `var`、`pub/static`、`pub/media`、`generated` 并调成 `www-data` 权限，保证被忽略的缓存目录可以在容器启动时动态落盘。

## 本地联调
```bash
docker network create magento

docker run -d --name php-fpm --network magento \
  -e MAGENTO_RUN_MODE=production \
  registry.ovh.net/kubemage/magento-php-fpm:dev

docker run -d --name web --network magento -p 8080:8080 \
  -e FASTCGI_PASS=php-fpm:9000 \
  registry.ovh.net/kubemage/magento-web:dev
```
访问 `http://localhost:8080` 验证。

## 与 CI 对齐
- `.github/workflows/build-magento.yml` 会依次执行 Composer/静态资源构建并构建三种镜像。
- 推送成功后请更新 `charts/magento/values-*.yaml` 的 `image.tag`，通过 GitOps/Helm 发版。

## 生成代码 Builder（多站点通用）
Magento CLI 每次运行都会擦除 `generated/`、`var/di/`，为了让 CronJob/消费者稳定运行，我们以 namespace 为单位准备可复用的生成物：

1. Helm Chart 会在每个租户 namespace 中创建 `*-generated` 与 `*-vardi` 两个 PVC，并在 CronJob/消费者 Pod 中挂载到 `/var/www/html/generated`、`/var/www/html/var/di`。
2. 每当代码或配置变更时，执行脚本 `scripts/magento-builder.sh <namespace> <release> <php-image:tag>`，以 PHP 镜像起一个一次性的 Job（可通过环境变量控制行为）：
   ```bash
  ./scripts/magento-builder.sh demo demo ghcr.io/ellistondow/kubemage-php:demo-0.1.3
  ./scripts/magento-builder.sh bdgy bdgy ghcr.io/ellistondow/kubemage-php:bdgy-0.1.3
   ```
   - `MAGENTO_BUILDER_COMPILE=1`：在 PVC 内执行 `setup:upgrade`/`setup:di:compile`；
   - `MAGENTO_BUILD_STATIC=1`：执行 `setup:static-content:deploy -f <locale>`，并把 `pub/static` 上传到 PVC（默认语言 `en_US`，可通过 `MAGENTO_STATIC_LOCALES="en_US zh_Hans_CN"` 覆盖；并发度可用 `MAGENTO_STATIC_JOBS=6` 设置）；
   - `MAGENTO_BUILDER_TTL=0`：保留 Job 以便排障（默认 300 秒后自动清理）。
   Job 结束后会把 `generated/`、`var/di/`、`pub/static/` 同步回 PVC，供 Web/PHP Pod 复用。
3. Job 成功后即可删除，CronJob/消费者 Pod 将直接复用 PVC 内的生成物；若后续升级模块，只需重新跑脚本即可。

> 建议把脚本执行后的日志与 Job 名称记录在 `docs/status.md`，便于排障与回滚。

## 站点代码准备
对于每一个 `app/sites/<site>`，需要先在裸机上跑一次 Composer 以便本地调试、构建镜像时可以直接复制完整依赖：

```bash
cd app/sites/<site>
docker run --rm \
  -v \"$PWD\":/var/www/html \
  -w /var/www/html \
  -e COMPOSER_ALLOW_SUPERUSER=1 \
  -e COMPOSER_AUTH='{\"http-basic\":{\"repo.magento.com\":{\"username\":\"<public-key>\",\"password\":\"<private-key>\"}}}' \
  composer:2.8 \
  install --no-dev --optimize-autoloader --prefer-dist --no-interaction --ignore-platform-reqs
```

> 提示：不要把 `auth.json` 提交到 Git，中继凭据请交由 CI Secret/SealedSecret 管理。
