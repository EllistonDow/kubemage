# Phase 3 目录总览

| 组件 | 目录 | 说明 |
| --- | --- | --- |
| Percona MySQL | percona/ | Operator helm values、PXC CR、S3 Secret 示例 |
| OpenSearch | opensearch/ | OpenSearchCluster CR、S3 Secret |
| RabbitMQ | rabbitmq/ | RabbitmqCluster、policy、用户 Secret |
| Valkey | valkey/ | Bitnami Valkey Helm values + Secret |
| Edge | edge/ | Varnish/Nginx ingress values、VCL Secret |

所有文件均通过 GitOps 发布；部署顺序建议：Percona → OpenSearch → RabbitMQ → Valkey → Edge。
