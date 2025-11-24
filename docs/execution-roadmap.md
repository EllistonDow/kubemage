# Kubemage 执行路线

1. **准备阶段**
   - `scripts/host-init.sh`：在 bm-a 执行，完成 Ubuntu 24.04 基线。
   - 填写 `cluster/phase1/kubeadm-config.yaml`、MetalLB 地址池等占位符。
2. **Phase 1**
   - `make phase1` 或 `scripts/phase1-deploy.sh`。
   - 输出：`artifacts/phase1/kubeadm-init.log`, `artifacts/phase1/sonobuoy.tar.gz`。
3. **Phase 2**
   - `make phase2`。
   - 在 GitOps 仓库创建 `clusters/kubemage-prod`，Argo Root 指向该路径。
   - 验证 ESO/Vault、监控/日志；截图保存到 `artifacts/phase2/`。
4. **Phase 3**
   - `make phase3`。
   - 按 runbook 完成备份演练，记录 S3/Snapshot IDs。
5. **Phase 4**
   - 准备镜像（CI），复制 `values-store-example.yaml` 为站点专用。
   - `make phase4 RELEASE=store1 NAMESPACE=store1 VALUES=charts/magento/values-store1.yaml`。
   - 执行 Magento Post-install 脚本，完成业务验证。
6. **Phase 5**
   - `make phase5 longhorn` 安装分布式存储。
   - `make phase5 velero` 应用备份策略。
   - 参考 `docs/phase5-node-expand.md` 加入 bm-b，并更新 Runbook/SLO。

附加：
- 每阶段完成后更新 `docs/status.md`、提交 Git commit。
- 所有命令使用当前 kubeconfig (`~/.kube/config`)，如需远程执行可在 Makefile 中覆写 `KUBECONFIG`。
