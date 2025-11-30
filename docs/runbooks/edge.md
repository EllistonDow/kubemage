# Edge 层 Runbook

## 组件
- Nginx Ingress Controller（ModSecurity + CRS）。
- Varnish Cache。
- Magento Web/PHP-FPM Deployment（Phase 4 部署）。

## 暴露模式
- **当前（2025-11-30）**：`gitops/platform/gitops/edge-ingress.yaml` 将 `ingress-nginx` 以 `hostNetwork + hostPort` 运行，并把 Service 设置为 `ClusterIP`，直接占用宿主机主 IP `51.222.241.152` 的 `80/443`。`argocd.k8s.bdgyoo.com`、`*.k8s.bdgyoo.com` DNS 必须指向该主 IP。
- **目标**：待所有站点迁移完成并执行 OVH MOVE 后，再把 `controller.hostNetwork` 关闭、`service.type` 调回 `LoadBalancer`，并在 `metallb-system` 中使用 `public-pool` 提供的 Failover IP（`144.217.149.203/32` 等）。
- 切换步骤：更新 `gitops/platform/gitops/edge-ingress.yaml` 对应 Helm values → `git commit` → `argocd app sync edge-ingress`，期间务必协调 DNS 及 Cloudflare/OVH。

## 日常检查
- `kubectl get pods -n ingress-nginx`, `kubectl logs -n edge deploy/varnish`. 
- Grafana dashboards：`Ingress Request Rate`, `Varnish HIT/MISS`。

## 常见操作
### 调整 ModSecurity 规则
1. 更新 ConfigMap/CRS overrides。
2. 通过 GitOps 提交 PR，Argo 同步。
3. 验证：`kubectl exec` 运行 `nginx -t`，再 `kubectl rollout restart deployment ingress-nginx-controller`。

### 缓存清理
- 全量：`kubectl exec deploy/varnish -- varnishadm ban "req.url ~ .*"`。
- 指定 URL：`varnishadm ban "req.url ~ /media/catalog/product"`。

### SSL/TLS
- 借助 cert-manager（Phase 4），证书保存在 `cert-manager` namespace。
- 续期失败时，查看 `kubectl describe certificate <name>`。

## 故障排查
- `502/504`：检查后端 PHP-FPM readiness，查看 `kubectl describe pod`。
- `WAF Block`：在 ModSecurity 日志中查 `id`，调整 CRS 规则。
- `MetalLB IP 不通`：验证 OVH 防火墙/vRack，检查 `metallb-controller` 日志。
