# GitOps / Argo CD 引导 Runbook

## 目标
在 Phase 2 中，引导 Argo CD 并让 `gitops/clusters/kubemage-prod` 作为根应用（App of Apps），从而自动部署 infra/platform/tenants/operations 资源。

## 前置条件
1. Phase 1 集群已完成（kube-vip、Cilium、MetalLB、OpenEBS 可用）。
2. `helm`, `kubectl`, `sops` 已安装并指向目标集群。
3. Git 仓库可通过 HTTPS 访问（本仓库默认 `https://github.com/EllistonDow/kubemage.git`）。

## 步骤
1. **可选：调整 Argo CD 暴露方式**
   - 在 `cluster/phase2/gitops/argocd-values.yaml` 中设置 `server.service.annotations.external-dns...` 或开启 Ingress。
   - 如果需要自签证书/公网域名，在 `server.ingress` 节点补充相应配置。
2. **部署 Argo CD**
   ```bash
   ./scripts/phase2-deploy.sh
   ```
   - 脚本会安装 Argo CD（Helm chart 5.53.0）、kured、ESO sample、Gatekeeper 模版、kube-prometheus-stack、Loki/Tempo 等基础栈。
   - 等待 `kubectl get pods -n argocd` 所有组件 Running。
   - 建议在执行前先运行 `make artifacts`，创建 `artifacts/phase2/` 以存放截图与 `kubectl get` 输出。
3. **配置 Root Application**
   - `cluster/phase2/gitops/argo-root.yaml` 已指向本仓库 `clusters/kubemage-prod`。
   - 运行 `kubectl apply -f cluster/phase2/gitops/argo-root.yaml`（脚本已包含）。
   - 在 Argo CD UI 或 CLI (`argocd app list`) 中确认 `kubemage-root` Healthy/Synced，并逐级检查 `clusters/kubemage-prod` 下的 Application/资源（特别是 ops/shared-* CronJob 与 tenants/demo、bdgy）。
4. **令牌与访问**
   - 默认 `argocd` 服务通过 MetalLB `public-pool` 暴露，域名示例：`argocd.kubemage.example.com`。
   - 初始密码可通过 `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`.
5. **管理员密码轮换**
   1. 生成高强度密码，例如 `python3 - <<'PY' ...`。
   2. 使用 `htpasswd -BinC 10 admin <password> | cut -d: -f2 | sed 's/$2y/$2a/'` 生成 bcrypt 哈希。
   3. `kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"admin.password":"<hash>","admin.passwordMtime":"<ISO8601>"}}'`。
   4. `kubectl -n argocd rollout restart deployment argocd-server && kubectl -n argocd rollout status deployment argocd-server`。
   5. 通过 `argocd login <host> --username admin --password '<password>' --insecure` 验证，再在密码保险库更新记录。
6. **SOPS 与 repoServer 配置**
   - `gitops/platform/gitops/argocd.yaml` 已挂载 `sops-age` Secret；在集群创建 `sops-age-key`（同 `scripts/sops-age-init.sh`）即可解密 tenants values。
7. **验证（并记录到 `artifacts/phase2/`）**
   - `argocd app get kubemage-root`：截图/导出 YAML，证明 App-of-Apps 成功。
   - `kubectl get cronjob -n ops shared-backup shared-monitor`：保存输出到 `artifacts/phase2/<date>-ops-cronjobs.txt`，保证 Phase3 CronJob 已经交由 GitOps 管理。
   - `kubectl get es secrets -A | grep external-secret`：确认 ESO 能取到 Vault/SecretStore。
   - `kubectl -n monitoring get pods` + Grafana/Alertmanager 截图：佐证 kube-prometheus-stack/Loki/Tempo 就绪。

## 故障排除
| 症状 | 处理 |
| --- | --- |
| Root App `Missing`/`OutOfSync` | 确认 `repoURL`、`targetRevision` 与当前仓库一致；必要时在 Argo CD UI 重新授权 HTTPS 访问。 |
| SOPS 解密失败 | 检查 `argocd-repo-server` Pod 是否挂载了 `sops-age` Secret；日志中若提示 `failed to open age identity`，需要重新创建密钥。 |
| 资源 apply 失败 | 通过 `kubectl logs deployment/argocd-application-controller -n argocd` 查看详细错误，可能是缺少 CRD/Helm repo。 |

完成上述步骤，即可进入 Phase 3，把共享依赖 / 站点 Helm Release 纳入 GitOps 管理。
