# 升级 Runbook

## Kubernetes 次版本升级
1. 备份 etcd：`ETCDCTL_API=3 etcdctl snapshot save /root/etcd-$(date +%s).db`。
2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`。
3. `apt-mark unhold kubeadm && apt-get install kubeadm=1.30.x`。
4. `kubeadm upgrade apply v1.30.x`（control-plane）或 `kubeadm upgrade node`（worker）。
5. 升级 kubelet/kubectl，重启 kubelet。
6. `kubectl uncordon <node>`。

## Magento 补丁
1. 在 staging Namespace 部署新 chart + 镜像。
2. 执行 `php bin/magento setup:upgrade`，跑回归测试。
3. GitOps PR 更新 production values。
4. `helm upgrade`，实时观测指标。
5. 如失败 `helm rollback` + PITR。

## Operator 升级
1. 在 `platform-canary` Namespace 复制 Operator。
2. 升级 Helm chart / manifest。
3. 观察 24h，无异常后更新生产 Operator。
