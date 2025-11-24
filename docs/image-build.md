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
