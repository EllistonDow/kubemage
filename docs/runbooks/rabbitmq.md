# RabbitMQ Runbook

## 健康检查
- 控制台：通过 `https://rabbitmq.kubemage.example.com` 查看。
- Metrics：`kubectl port-forward svc/magento-mq 15692 -n messaging` 并查看 Prometheus。
- CLI：
```bash
kubectl exec -n messaging magento-mq-server-0 -- rabbitmq-diagnostics -q status
kubectl exec -n messaging magento-mq-server-0 -- rabbitmq-queues list name durable consumers messages_ready
```

## 常见操作
### 1. 用户/权限
```bash
kubectl exec -n messaging magento-mq-server-0 -- rabbitmqctl add_user api_user strongpass
kubectl exec -n messaging magento-mq-server-0 -- rabbitmqctl set_permissions -p / api_user ".*" ".*" ".*"
```
### 2. 队列堆积
- 查看 `messages_ready`，若 > 阈值：
  - 增加 Magento 消费者副本数（HPA/KEDA）。
  - 检查 Valkey、MySQL 是否成为瓶颈。
### 3. 升级流程
1. `kubectl edit rabbitmqcluster magento-mq`，修改 `image`。
2. Operator 会滚动升级节点；监控 `kubectl get pods`。

## 备份策略
- 使用 `rabbitmq-plugins enable rabbitmq_shovel` + S3 shovel（后续 Phase 5）。
- 短期内通过 `kubectl exec ... rabbitmqctl export_definitions /tmp/defs.json` 并上传对象存储。

## 故障
- `File descriptor limit`: 调整 StatefulSet 模板 `ulimits`。
- 节点 down：`kubectl delete pod` 让 Operator 重建，若磁盘损坏需恢复 PVC（ZFS snapshot）。
