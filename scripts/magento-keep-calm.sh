#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "用法: $0 <namespace> <release> [extra kubectl args...]" >&2
  exit 1
fi

NAMESPACE=$1
RELEASE=$2
shift 2 || true
KUBECTL_ARGS=("$@")
TARGET="deploy/${RELEASE}-magento-php"
run_magento() {
  local cmd=(kubectl exec -n "$NAMESPACE" "${KUBECTL_ARGS[@]}" "$TARGET" -- php bin/magento "$@")
  echo "[keep-calm] ${cmd[*]}"
  "${cmd[@]}"
}

echo "[keep-calm] 切换 maintenance 模式"
run_magento maintenance:enable || true

echo "[keep-calm] 导入配置 & 升级 schema"
run_magento app:config:import --no-interaction || true
run_magento setup:upgrade --keep-generated

echo "[keep-calm] 刷新代码/缓存"
run_magento cache:flush
run_magento cache:clean

echo "[keep-calm] 重新索引"
run_magento indexer:reindex

echo "[keep-calm] 重启异步消费者"
run_magento queue:consumers:restart async.operations.all || true

echo "[keep-calm] 关闭 maintenance 模式"
run_magento maintenance:disable || true

echo "[keep-calm] 全部完成"
