# Alertmanager 告警 Runbook（Phase 2）

1. **告警来源**：
   - Prometheus -> Alertmanager -> Slack Webhook（默认）
   - 严重级别 `critical` -> PagerDuty `oncall` 接收。
2. **首要动作**：
   - 在 Grafana Dashboard 查看对应面板，确认是否为噪声。
   - 通过 `kubectl get events -A` 和 `kubectl describe pod` 获取上下文。
3. **常见告警处理**：
   - `KubeNodeNotReady`: 检查 `node-problem-detector` 日志、宿主机系统日志；如硬件故障，触发 failover。
   - `KubePodCrashLooping`: 先查看对应 Namespace 的 Config/Secret 是否最近变更（查 Git commit）。
   - `PrometheusTargetMissing`: 确认 ServiceMonitor/Endpoint 是否被 Argo CD prune。
4. **升级路径**：
   - 若 30 分钟无法恢复，升级至 SRE 负责人，记录于 incident doc。
5. **事后复盘**：
   - 导出 Alertmanager 历史、Grafana 图表，归档在 `runbooks/incidents/<date>.md`。
