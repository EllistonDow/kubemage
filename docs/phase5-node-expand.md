# 第二台裸机 (bm-b) 加入流程

## 1. 宿主机准备
- 重复 `scripts/host-init.sh`（修改 HOSTNAME 为 bm-b）。
- 配置 vRack/私网，与 bm-a 互通。
- 将 kubeadm token/certs 复制到安全位置。

## 2. kubeadm Join
```bash
sudo kubeadm join k8s-vip.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key>
```

## 3. 验证
```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -l component=kube-apiserver
kubectl get endpoints kube-apiserver -n default
```
确认 etcd 成员：
```bash
kubectl -n kube-system exec -it etcd-bm-a -- etcdctl member list
```

## 4. 调整调度
- 为控制面节点去除 `NoSchedule` taint（若计划承载 workload）：
```bash
kubectl taint nodes bm-b node-role.kubernetes.io/control-plane:NoSchedule-
```
- 给 bm-b 打标签：`node-role.kubernetes.io/infra="true"`。

## 5. StatefulSet 扩容
- 修改 Percona/OpenSearch/RabbitMQ/Valkey CR，使副本数 >=2。
- 添加 `podAntiAffinity`、`topologySpreadConstraints`（示例在 `cluster/phase5/anti-affinity-patch.yaml`）。
- 观察 PV 调度，必要时迁移到 Longhorn。

## 6. kured / Drain
- 在升级或维护前：`kubectl drain bm-a --ignore-daemonsets --delete-emptydir-data`。
- 完成后 `kubectl uncordon bm-a`。

## 7. 记录
- 更新 `docs/capacity-plan.md`（节点资源）。
- 在 Incident 模板写入“节点扩容”条目以备审计。
