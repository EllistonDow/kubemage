# Edge 镜像与 CI/CD

## 1. 镜像分类
1. `kubemage/magento-web`: Nginx 1.28 + Magento 静态资源。
2. `kubemage/magento-php-fpm`: PHP 8.3-FPM + opcache + required extensions。
3. `kubemage/magento-cron`: 复用 PHP 镜像，附加 cron entry。

## 2. Dockerfile 要点
- 基于 `ubuntu:24.04` 或 `ghcr.io/adobecommerce/php:8.3-fpm`。
- 安装扩展：`bcmath`, `ctype`, `curl`, `dom`, `gd`, `intl`, `mbstring`, `pdo_mysql`, `soap`, `sockets`, `sodium`, `xsl`, `zip`。
- 使用 `composer install --no-dev --optimize-autoloader`，随后 `bin/magento setup:di:compile`、`setup:static-content:deploy`。
- 将生成的 `generated/`, `pub/static/`, `vendor/` 缓存进构建层。

## 3. CI 流水线（示例 GitHub Actions）
1. 触发：`main` 分支 push 或手动调度。
2. 步骤：
   - `actions/checkout` + `setup-php`（Composer 2.8）。
   - `composer install` + `npm ci`（如需 theme build）。
   - `bin/magento setup:di:compile`。
   - `bin/magento setup:static-content:deploy -f en_US zh_CN`。
   - `docker buildx build` 多架构（linux/amd64）。
   - 推送 Harbor/OVH Registry（带 git sha tag）。
3. 产物：镜像标签 `magento-web:<git-sha>`，`magento-php-fpm:<git-sha>`。

## 4. GitOps 集成
- 在 `tenants/<store>/values.yaml` 中引用镜像标签。
- CI 完成后通过 GitOps PR 更新 `values.yaml`，由 Argo CD 部署。

## 5. 安全
- 扫描：Trivy/Snyk 在 CI 中扫描镜像。
- SBOM：`cosign attest --predicate sbom.spdx.json`。
- 签名：`cosign sign` 并在 Kubernetes 中启用 Cosign policy（可在 Phase 5 进行）。
