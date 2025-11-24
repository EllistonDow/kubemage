# Kubemage SLO / Error Budget

| 服务 | 指标 | SLO | 监控 | 预算 |
| --- | --- | --- | --- | --- |
| Storefront | 可用率 (HTTP 2xx/3xx) | >= 99.9% / 30d | Ingress metrics via Prometheus | 43.2 min 停机 | 
| Checkout API | p95 响应时间 | <= 2s | Magento APM (OTel -> Tempo/Grafana) | 超过即消耗预算 |
| Search | p95 响应 | <= 1s | OpenSearch Dashboards | 若>1s 连续 2h 上报 |
| Cron/Consumers | 成功率 | >= 99% | KEDA + Prometheus job metrics | 7.2h/月 |

## 流程
1. 每周审查 Grafana SLO 面板。
2. 若误差 > 20%（预算消耗快速），召开 Error Budget Review，暂停新功能发布。
3. Incident 结束后更新 `runbooks/incident-template.md`。
