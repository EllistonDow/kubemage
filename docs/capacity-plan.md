# 容量规划（初版）

| 组件 | 当前配置 | 峰值指标 | 扩容阈值 | 行动 |
| --- | --- | --- | --- | --- |
| Magento PHP | 2×4vCPU / 4Gi | CPU 65% | 75% | 提前增加 2 副本或调大 HPA max |
| MySQL PXC | 1 节点 8c/32Gi | CPU 40%，IOPS 5k | CPU 70% 或 IOPS 10k | 扩展 replica + 调高 buffer pool |
| OpenSearch | 1 节点 6c/24Gi/1Ti | JVM 60% | JVM 75% | 增加 data node，并启用 warm tier |
| RabbitMQ | 1 节点 4c/8Gi | Messages_ready < 5k | >20k 或 Rate 5k/s | 扩容节点并增加 quorum queues |
| Valkey | 主 4c/16Gi + 从 4c/16Gi | 内存 50% | 70% | 增加副本或分片 |

监控指标来自 Prometheus/Grafana：
- `container_cpu_usage_seconds_total`
- `mysql_global_status_bytes_sent`
- `opensearch_jvm_memory_used_bytes`
- `rabbitmq_queue_messages_ready`
- `redis_memory_used_bytes`

未来第二台服务器上线后，目标是：
- PHP/Web 副本 >=4 (spread across 2 nodes)
- MySQL replica 1，OpenSearch data node 2，RabbitMQ 2 节点，Valkey 2+Sentinel 3
