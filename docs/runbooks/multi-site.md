# 多站点容器化运行手册

适用于当前 repo 的 docker-compose 部署（`infra/`），指导如何在 **共享基础依赖**（Percona / OpenSearch / RabbitMQ / Valkey） 的前提下，为每个 Magento 站点构建独立的 PHP/Web/Varnish 栈，并通过统一的 Edge Nginx/SSL 网关对外提供服务。

---

## 目录结构

```
infra/
├── shared/                   # 共享依赖栈（Percona/OpenSearch/RabbitMQ/Valkey）
│   └── docker-compose.yml
├── docker-compose.yml        # 单站点栈（PHP/Web/Varnish/Cron），连接共享依赖
├── sites/
│   └── <site>/
│       ├── .env              # 站点变量（SITE_NAME / SITE_DIR）
│       └── nginx.conf        # 站点专属虚拟主机
└── edge/                     # 统一入口，反向代理到各站点 Varnish
    ├── docker-compose.yml
    └── nginx.conf
```

每个站点仍然使用独立的代码目录 `app/sites/<site>`，但数据库/搜索/消息队列/Redis 都由 `infra/shared` 的一套容器对外提供，防止资源浪费并便于集中运维。

---

## 1. 启动共享依赖层（只需一次）

```bash
cd /home/doge/kubemage/infra/shared
docker-compose up -d
```

创建完成后会得到容器：`percona`、`opensearch`、`rabbitmq`、`valkey`，全部挂在 `magento-shared` 网络。首次部署请按以下步骤初始化：

1. **数据库（Percona）**
   ```bash
   docker exec percona mysql -uroot -pPerconaRoot!2025 \
     -e "CREATE DATABASE <db>; CREATE USER '<user>'@'%' IDENTIFIED BY '<pass>'; GRANT ALL ON <db>.* TO '<user>'@'%'; FLUSH PRIVILEGES;"
   ```
   - 每个站点自建一个 schema & 用户，例如 `bdgymage/bdgy`、`magento/demo`。
   - 导入 SQL 备份：`cat dump.sql | docker exec -i percona mysql -uroot -pPerconaRoot!2025 <db>`.

2. **RabbitMQ vhost**
   ```bash
   docker exec rabbitmq rabbitmqctl add_vhost /<site>
   docker exec rabbitmq rabbitmqctl set_permissions -p /<site> magento ".*" ".*" ".*"
   ```
   站点的 `app/etc/env.php` 中 `queue.amqp` 需指向自己的 vhost（如 `/bdgy`、`/demo`），用户/密码共用 `magento/magentoPass`。

3. **Valkey (Redis)**
   - 所有站点共用一个实例，但必须使用不同的 database id（Valkey 默认仅提供 0~15 共 16 个 DB）。
   - 建议每个站点占用 4 个 DB：默认缓存 / FPC / Session / PageCache，例如：
     - bdgy：2 / 3 / 4 / 5
     - demo：8 / 9 / 10 / 11

4. **OpenSearch**
   - 站点在 `core_config_data` 的 `catalog/search/opensearch_*` 中指定 `host=opensearch`、`index_prefix` 区分。

共享层重启后数据会保留在命名卷（`percona-data` 等）中。

---

## 2. 准备站点环境

1. **复制模板**
   ```bash
   cp -r infra/sites/demo infra/sites/<site>
   ```

2. **编辑 `.env`**

   | 变量        | 含义                                                                                |
   | ----------- | ----------------------------------------------------------------------------------- |
   | `SITE_NAME` | 站点代号，用于容器/Edge alias                                                       |
   | `SITE_DIR`  | 代码目录（`app/sites/<site>`）                                                      |
   | `SITE_DOMAIN` (可选) | 仅用于记录目标域名，Edge 配置时参考                                      |

3. **准备 `nginx.conf`**

   至少包含：
   ```nginx
   upstream fastcgi_backend { server php-fpm:9000; }

   server {
       listen 80;
       server_name <site-domain>;
       client_max_body_size 50m;
       set $MAGE_ROOT /var/www/html;
       include /var/www/html/nginx.conf.sample;
   }
   ```

   PHP-FPM 端口固定走 `php-fpm:9000`，其余 SSL/反向代理由 Edge 负责。

---

## 3. 启动站点容器

```bash
cd /home/doge/kubemage
docker-compose \
  --env-file infra/sites/<site>/.env \
  -f infra/docker-compose.yml \
  -p <site> up -d
```

该命令只会启动站点专属容器：

- `php-fpm` / `cron`（引用 `app/sites/<site>`）
- `web`（Nginx+ModSecurity，使用 `infra/sites/<site>/nginx.conf`）
- `varnish`（backend 指向 `web`，同时加入 `magento-edge` 网络）

站点服务将自动连接到共享依赖（percona/opensearch/rabbitmq/valkey）。完成首次部署后，请在 `app/sites/<site>/app/etc/env.php` 中确认以下内容：

1. **数据库**：`db.connection.default` 指向 `percona`，账号/库名为共享层中创建的值。
2. **AMQP**：`queue.amqp.virtualhost = '/<site>'`。
3. **Redis**：`cache.frontend.default.backend_options.database` 等 4 个 DB ID 与其他站点不冲突。
4. **Varnish/Edge**：`http_cache_hosts` 中 host = `varnish`。

然后执行：

```bash
docker exec -u www-data <site>_php-fpm_1 php -d memory_limit=-1 bin/magento setup:upgrade
docker exec -u www-data <site>_php-fpm_1 php -d memory_limit=-1 bin/magento setup:di:compile
docker exec -u www-data <site>_php-fpm_1 php -d memory_limit=-1 bin/magento setup:static-content:deploy -f
docker exec -u www-data <site>_php-fpm_1 php -d memory_limit=-1 bin/magento cache:flush
docker exec -u www-data <site>_php-fpm_1 php -d memory_limit=-1 bin/magento indexer:reindex
```

> 提示：站点命令只作用于 `<site>` 前缀容器；共享依赖不必频繁重启。

---

## 4. Edge 网关（多域名汇聚）

Edge 位于 `infra/edge`，只需部署一次：

```bash
cd /home/doge/kubemage/infra/edge
docker-compose up -d
```

功能：

- 监听宿主 `80/443`，自动把 HTTP 重定向到 HTTPS。
- 针对不同 `server_name` 代理至 `magento-edge` 网络中的 `<site>-varnish`。

步骤：

1. 确保每个站点的 `varnish` 服务加入 `magento-edge` 网络（docker-compose 模板已在 `networks.edge.aliases` 中设定）。
2. 在 Edge Nginx 配置 (`infra/edge/nginx.conf`) 中增加相应 upstream & server 块，例如：
   ```nginx
   upstream foo_varnish { server foo-varnish:6081; }

   server {
       listen 443 ssl;
       http2 on;
       server_name foo.k8s.bdgyoo.com;
       ssl_certificate /etc/letsencrypt/live/foo.k8s.bdgyoo.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/foo.k8s.bdgyoo.com/privkey.pem;
       ...
       location / {
           proxy_set_header Host $host;
           proxy_set_header X-Forwarded-Proto https;
           proxy_pass http://foo_varnish;
       }
   }
   ```
3. 通过 `certbot certonly --standalone -d <domain>` 申请证书，Edge 容器挂载 `/etc/letsencrypt` 后即可使用。
4. 修改完配置，执行：
   ```bash
   docker exec edge_edge_1 nginx -s reload
   ```

---

## 5. 常见维护

| 操作                         | 命令示例                                                                 |
| ---------------------------- | ------------------------------------------------------------------------ |
| 查看站点容器状态            | `docker ps --filter "name=<site>_"`                                      |
| 进入站点 PHP Shell          | `docker exec -it <site>_php-fpm_1 bash`                                  |
| 导入数据库                  | `cat backup.sql | docker exec -i percona mysql -uroot -p... <db>`           |
| 新增 RabbitMQ vhost         | `docker exec rabbitmq rabbitmqctl add_vhost /<site>`                     |
| Valkey 清理                 | `docker exec valkey redis-cli -n <db> FLUSHDB`                           |
| 重启 Edge                   | `docker exec edge_edge_1 nginx -s reload`                                |
| 停止单站点                  | `docker-compose --env-file ... -p <site> down`                           |

---

## 6. Kubernetes 对应

在 K8s 中可以将本方案映射为「每个站点一个 Helm Release」：

- `Deployment`：php-fpm / web / varnish / cron / consumers
- `StatefulSet`：Percona、OpenSearch、RabbitMQ、Valkey（或对接集群级 Operator）
- `Ingress`：对应站点域名 → web service，证书交给 cert-manager

Edge 逻辑由 Ingress Controller、WAF（Nginx/ModSecurity）、Gateway API 来实现，与 docker-compose 版理念一致。

> 需要完整的 K8s 迁移路线，可参考 `docs/runbooks/k8s-migration.md`，其中包含 Operator/Helm/GitOps 的分阶段规划。

---

## 7. 共享层备份与监控

共享的 Percona / OpenSearch 已经放入 `scripts/` 中的自动化脚本：

| 场景 | 命令 | 说明 |
| --- | --- | --- |
| 手工/定时备份 | `./scripts/shared-backup.sh` | 默认输出到 `artifacts/shared-backups/`，包含 `percona_*.sql.gz` 与 `opensearch_*.tar.gz`。内部逻辑：mysqldump 全库备份 + OpenSearch FS snapshot（通过 `docker exec $OPENSEARCH_CONTAINER curl ...` 调用 API，不暴露宿主端口）。可通过 `BACKUP_ROOT`、`PERCONA_ROOT_PASSWORD`、`OPENSEARCH_CONTAINER`、`OPENSEARCH_ENDPOINT`、`BACKUP_RETENTION_DAYS` (默认 7 天) 覆盖。建议 crontab：`0 3 * * * BACKUP_RETENTION_DAYS=14 /home/doge/kubemage/scripts/shared-backup.sh >> /var/log/kubemage-backup.log 2>&1`. |
| 健康检查/集成监控 | `./scripts/shared-monitor.sh` | 校验 `percona` 容器可用、输出关键指标（Uptime/Threads_connected 等），同时通过 `docker exec $OPENSEARCH_CONTAINER curl ...` 抓取 OpenSearch `_cluster/health` 与 `_cat/nodes`。若检测到 OpenSearch `status=red` 则退出码为 2，方便接入 Prometheus `node_exporter`/cron 报警。可通过 `PERCONA_CONTAINER`、`PERCONA_ROOT_PASSWORD`、`OPENSEARCH_CONTAINER`、`OPENSEARCH_ENDPOINT` 变量定制。 |

> OpenSearch 快照目录绑定到 `artifacts/opensearch-snapshots/`（参见 `infra/shared/docker-compose.yml`），脚本会以 `snap_<timestamp>` 为单位创建临时仓库、生成快照并打包压缩，随后自动清理快照仓库，确保存储空间可控。

备份产物可直接用来回滚：

1. **Percona**：`zcat artifacts/shared-backups/percona/percona_<ts>.sql.gz | docker exec -i percona mysql -uroot -p...`。
2. **OpenSearch**：解压 `opensearch_<ts>.tar.gz` 至 `artifacts/opensearch-snapshots/`，重新注册仓库后执行 `POST /_snapshot/<repo>/full/_restore`。

建议在 Prometheus/Alertmanager 中订阅 `shared-monitor.sh` 的输出（或通过 `systemd`/`cron` 发送到 `logger`），并在任意站点部署/升级前执行一次 `shared-backup.sh` 形成可回滚快照。
