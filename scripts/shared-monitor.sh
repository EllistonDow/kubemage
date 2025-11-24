#!/usr/bin/env bash

set -euo pipefail

PERCONA_CONTAINER="${PERCONA_CONTAINER:-percona}"
PERCONA_ROOT_PASSWORD="${PERCONA_ROOT_PASSWORD:-PerconaRoot!2025}"
OPENSEARCH_CONTAINER="${OPENSEARCH_CONTAINER:-opensearch}"
OPENSEARCH_ENDPOINT="${OPENSEARCH_ENDPOINT:-http://127.0.0.1:9210}"

log() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"
}

check_percona() {
  log "检查 Percona (${PERCONA_CONTAINER})"
  docker exec "$PERCONA_CONTAINER" sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysqladmin ping -uroot" >/dev/null

  local status
  status=$(docker exec "$PERCONA_CONTAINER" sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysql -uroot --batch --skip-column-names -e \"SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_connected','Threads_running','Questions');\"")

  printf "Percona 全局状态 (name=value)：\n%s\n" "$status"

  local disk
  disk=$(docker exec "$PERCONA_CONTAINER" du -sh /var/lib/mysql 2>/dev/null | awk '{print $1}')
  log "Percona 数据目录占用: ${disk:-unknown}"
}

check_opensearch() {
  log "检查 OpenSearch (${OPENSEARCH_CONTAINER})"
  local health_json
  health_json=$(docker exec "$OPENSEARCH_CONTAINER" curl -sf "$OPENSEARCH_ENDPOINT/_cluster/health")
  local status
  status=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))" <<<"$health_json")

  printf "OpenSearch cluster status: %s\n" "$status"
  docker exec "$OPENSEARCH_CONTAINER" curl -sf "$OPENSEARCH_ENDPOINT/_cat/nodes?v" || true

  if [[ "$status" == "red" ]]; then
    log "OpenSearch 状态 red，退出"
    exit 2
  fi
}

check_percona
check_opensearch

log "共享依赖监控检查完成"
