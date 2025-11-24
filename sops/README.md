# SOPS + age 密钥管理

## 1. 初始化 age key
```bash
age-keygen -o age.key
mkdir -p ~/.config/sops/age
mv age.key ~/.config/sops/age/keys.txt
```
将公钥写入 `sops/age.pub`，供团队共享。

## 2. .sops.yaml 配置（放在 GitOps 仓库根目录）
```yaml
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml
    encrypted_regex: '^(data|stringData)$'
    age: ["age1qf...yourkey"]
```

## 3. 加密示例
```bash
sops --encrypt secrets/mysql.enc.yaml > secrets/mysql.enc.yaml
```
文件结构：
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: magento-db
  namespace: store1
stringData:
  MYSQL_PASSWORD: supersecret
```

## 4. 在 Argo CD 使用 SOPS
- 创建 `sops-age-key` secret：
```bash
kubectl -n argocd create secret generic sops-age-key \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```
- `argocd-repo-server` 已在 `argocd-values.yaml` 中挂载该 secret。
- GitOps 仓库提交的加密文件需以 `.enc.yaml` 后缀区分。

## 5. CI 验证
在 GitOps 仓库的 CI 中运行：
```bash
sops --decrypt secrets/mysql.enc.yaml >/tmp/mysql.yaml
kubeconform /tmp/mysql.yaml
```
确保密钥仅在安全环境解密。
