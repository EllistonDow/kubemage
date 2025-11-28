# SOPS 密钥与 Secrets 管理

> 说明如何使用 age 私钥对 `gitops/tenants/*/secrets.enc.yaml` 进行加解密、轮换与分发。

## 目录结构
```
.sops.yaml                      # SOPS 规则（匹配 gitops/tenants/.*/secrets.enc.yaml）
sops/age.pub                    # 团队共享的 age 公钥
~/.config/sops/age/keys.txt     # 每位运维本地保存的 age 私钥（不提交）
```
- GitOps 仓库内的所有 `gitops/tenants/<site>/secrets.enc.yaml` 均使用上述公钥加密。
- Argo CD 在部署时直接引用已经解密的 Kubernetes Secret（`<site>-magento-secrets`），Chart 中 `secrets.create=false`、`secrets.name` 指定该 Secret。

## 加解密操作
```bash
# 编辑并自动加密
sops gitops/tenants/demo/secrets.enc.yaml

# 解密预览（可管道到 kubectl）
sops --decrypt gitops/tenants/demo/secrets.enc.yaml | kubectl apply -f -
```
> 默认使用 `~/.config/sops/age/keys.txt` 中的私钥。首次操作需将私钥复制到该路径，权限 600。

## 轮换/分发建议
1. 如果需要新增成员，可以给他 `sops/age.pub`，让其生成新的 age 私钥即可解密，无需变更仓库。
2. 若公钥/私钥泄露，则：
   - 生成新的 age key，更新 `sops/age.pub` 与 `.sops.yaml` 中的配置；
   - 重新运行 `sops --encrypt --in-place` 对所有 `*.enc.yaml` 进行重加密；
   - 将新私钥安全分发。
3. Secrets 内容本身不会自动轮换，仍需根据需要用 `sops` 编辑，随后 `git commit` + `argocd app sync <site>`。

## 取回当前密码
只要有服务器 SSH 权限且持有 age 私钥，即可执行 `sops --decrypt gitops/tenants/<site>/secrets.enc.yaml` 拿到所有密码；或者：
```bash
kubectl -n <ns> get secret <site>-magento-secrets -o yaml | sops --decrypt
```
请妥善保管私钥（只存放在管理节点、必要时使用密码管理器），并定期审计拥有权限的人员清单。
