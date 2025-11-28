# Google PageSpeed / Lighthouse CI

> 目标：按需运行 Google PageSpeed Insights/Lighthouse 测试，生成可追溯的性能报表，并且能通过环境变量快速开启或关闭。

## 工具概览
- `scripts/pagespeed.sh`：调用 `@lhci/cli`，默认使用 PageSpeed Insights（`method=psi`），也可切到本地 Chrome（`method=node`）。
- `scripts/pagespeed.lhci.config.js`：Lighthouse CI 配置，基于环境变量注入 URL、运行次数、分数阈值、PSI 策略等。
- 报表输出目录：`artifacts/pagespeed/<UTC 时间戳>/`，包含 PSI/Lighthouse JSON、HTML、断言结果，可上传到任何制品库。

默认 `PAGESPEED_ENABLED=false`，脚本立即退出；按需设置为 `true` 即可开启，跑完后不设置就是“关闭”。

## 一次性手动执行
```bash
export PAGESPEED_ENABLED=true
export PAGESPEED_URLS=$'https://magento.k8s.bdgyoo.com/\nhttps://magento.k8s.bdgyoo.com/customer/account/login'
export PAGESPEED_METHOD=psi         # psi(默认) / node
export PAGESPEED_PSI_STRATEGY=mobile   # psi 模式下 mobile/desktop
export PAGESPEED_PRESET=mobile         # node 模式下 desktop/mobile
export PAGESPEED_RUNS=3                # 每个 URL 重复次数
# 可选阈值 (触发 warn)：
export PAGESPEED_MIN_SCORE=0.65
export PAGESPEED_A11Y_MIN_SCORE=0.80
export PAGESPEED_BP_MIN_SCORE=0.85
export PAGESPEED_SEO_MIN_SCORE=0.90

./scripts/pagespeed.sh
```
- 如果只想测试单个 URL，`PAGESPEED_URLS="https://demo.example.com"` 即可。
- `psi` 模式直接调用 Google PageSpeed Insights API，可设置 `PAGESPEED_PSI_API_KEY` 提升速率；若只做偶发测试可不设。
- 如需离线或内网压测，可 `export PAGESPEED_METHOD=node`。脚本会自动用 `@puppeteer/browsers` 下载 Chrome（缓存到 `.cache/pagespeed`），并传入 `LHCI_CHROME_FLAGS`；必要时也可以预装好 Chrome 并通过 `PAGESPEED_CHROME_PATH` 指定。
- 运行成功后，命令行会输出报表路径，例如 `artifacts/pagespeed/20251128-031045Z/`。

## 在 CI 中启用/禁用
1. GitHub 手动任务：`PageSpeed Audit` workflow（`.github/workflows/pagespeed.yml`）封装了该脚本，可在 Actions 页面输入 URL/method 并复用仓库 Secrets（`PAGESPEED_PSI_API_KEY`）。
2. 自建 pipeline 时，将 `scripts/pagespeed.sh` 作为步骤，默认为 `PAGESPEED_ENABLED=false`；需要回归时通过变量把它设为 `true` 并注入 URL/模式。
3. 如果担心 Lighthouse 外网访问暴露 staging，可先 `kubectl port-forward` 或在 VPN 内执行脚本；完成后恢复默认（不设置 env 即为“关闭”）。

## 解读结果
- `*.report.html`：完整 Lighthouse 报表，可本地打开查看每个指标。
- `lhr-*.json`：原始结果，便于后续做趋势分析或上传到 BigQuery/Looker。
- `assertion-results.json`：若得分低于阈值，脚本仍返回 0，但文件内会列出警告，方便在 CI 中做自定义处理（例如只在低于 0.5 时失败）。
- 结合 Grafana 的实测 RUM 指标，可区分真实问题 vs. Lighthouse 实验环境噪音。

## 常见问题
- **想暂时停用**：不要导出 `PAGESPEED_ENABLED` 或显式设置为 `false`，脚本会立即返回，避免浪费时间。
- **URL 需要登录**：先在浏览器获取 `storageState` 并用 Playwright 等工具预热，或为测试环境临时关闭登录，跑完再恢复。
- **得分波动大**：适当提高 `PAGESPEED_RUNS`（例如 5 次）或在相同地区的服务器跑，减少网络抖动。
- **Chrome 无法启动**：若必须用 `node` 模式，可提前在容器/节点安装 `libatk`, `libgtk-3` 等依赖，或使用 `PAGESPEED_CHROME_PATH` 指向自带的 Chrome headless；否则继续维持 `psi` 模式即可。
