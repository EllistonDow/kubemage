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

## 回滚
1. 找到上一版本 Helm release：`helm history store1 -n store1`。
2. `helm rollback store1 <REVISION>`。
3. 如果数据库 schema 变更不兼容，使用 Percona PITR 恢复相应时间点。
4. 回滚完成后运行 `php bin/magento cache:flush`。

## 常见问题
- **部署卡在 Pending**：检查 Namespace ResourceQuota、PVC 是否绑定、Cilium NetworkPolicy。
- **健康探针失败**：审查 FPM/Nginx 日志，确认 ENV/Secrets 是否正确。
- **队列积压**：增加 Consumers、副本或调高 RabbitMQ limits。

## 发布前检查表
- [ ] 镜像扫描通过（Trivy）。
- [ ] Helm values 经 `helm template` 验证。
- [ ] GitOps PR 已审核。
- [ ] 运行 `kubectl diff`（如果 GitOps 外部署）。
- [ ] CDN/DNS 已指向新环境。
