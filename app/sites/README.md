# Magento Sites Layout

- 每个站点的完整 Magento 代码位于 `app/sites/<site>`，当前演示站为 `app/sites/demo`。
- 本地开发/CI 命令（Composer、`bin/magento` 等）需在对应站点目录中执行，例如 `cd app/sites/demo`.
- 新增站点时：
  1. 复制 `app/sites/demo` 为 `app/sites/<new-site>` 并调整 `app/etc/env.php`、主题/模块等。
  2. 在 CI（`SITE_DIR`/`SITE_PATH`）、docker-compose 或 Helm values 中指定新的目录和镜像标签。
  3. 运行 `bin/magento setup:upgrade`、`setup:di:compile`、`cache:flush`，确认权限 (`var`, `generated`, `pub/static`, `pub/media`) 对 `www-data` 可写。
