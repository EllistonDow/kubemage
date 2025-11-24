#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/artifacts/shared-backups}"
SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-$ROOT_DIR/artifacts/opensearch-snapshots}"
PERCONA_CONTAINER="${PERCONA_CONTAINER:-percona}"
OPENSEARCH_CONTAINER="${OPENSEARCH_CONTAINER:-opensearch}"
OPENSEARCH_ENDPOINT="${OPENSEARCH_ENDPOINT:-http://127.0.0.1:9210}"
PERCONA_ROOT_PASSWORD="${PERCONA_ROOT_PASSWORD:-PerconaRoot!2025}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_ROOT/percona" "$BACKUP_ROOT/opensearch" "$SNAPSHOT_ROOT"

log() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"
}

require_container() {
  local name="$1"
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    log "ERROR: container '$name' 不存在或未运行"
    exit 1
  fi
}

backup_percona() {
  require_container "$PERCONA_CONTAINER"
  local outfile="$BACKUP_ROOT/percona/percona_${TIMESTAMP}.sql.gz"
  log "开始备份 Percona → $outfile"
  docker exec "$PERCONA_CONTAINER" sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysqldump -uroot --single-transaction --quick --routines --events --triggers --all-databases" \
    | gzip -c >"$outfile"
  log "Percona 备份完成 (${outfile})"
}

backup_opensearch() {
  require_container "$OPENSEARCH_CONTAINER"
  local repo_name="snap_${TIMESTAMP}"
  local repo_location="/usr/share/opensearch/snapshots/${repo_name}"
  local outfile="$BACKUP_ROOT/opensearch/opensearch_${TIMESTAMP}.tar.gz"

  log "准备 OpenSearch 快照仓库 ${repo_name}"
  mkdir -p "$SNAPSHOT_ROOT/${repo_name}"
  chmod 0777 "$SNAPSHOT_ROOT/${repo_name}"

  local register_payload
  register_payload=$(cat <<JSON
{"type":"fs","settings":{"location":"${repo_location}","compress":true}}
JSON
)

  local register_code
  register_code=$(printf '%s' "$register_payload" | docker exec -i "$OPENSEARCH_CONTAINER" curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}" \
    -H 'Content-Type: application/json' --data-binary @-)

  if [[ "$register_code" != "200" && "$register_code" != "201" ]]; then
    log "ERROR: 注册 OpenSearch 仓库失败 (HTTP $register_code)"
    exit 1
  fi

  log "创建 OpenSearch 快照 ${repo_name}/full"
  local snapshot_payload='{"indices":"*","ignore_unavailable":true,"include_global_state":true}'
  local snapshot_response
  snapshot_response=$(printf '%s' "$snapshot_payload" | docker exec -i "$OPENSEARCH_CONTAINER" curl -s -w "\n%{http_code}" -X PUT \
    "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}/full?wait_for_completion=true" \
    -H 'Content-Type: application/json' --data-binary @-)
  local snapshot_code
  snapshot_code=$(printf '%s' "$snapshot_response" | tail -n1)
  local snapshot_body
  snapshot_body=$(printf '%s' "$snapshot_response" | sed '$d')

  if [[ "$snapshot_code" != "200" && "$snapshot_code" != "201" ]]; then
    log "ERROR: 创建快照失败，详情：$snapshot_body"
    exit 1
  fi

  log "打包 OpenSearch 快照 → $outfile"
  tar -C "$SNAPSHOT_ROOT" -czf "$outfile" "$repo_name"

  log "清理临时快照仓库"
  docker exec "$OPENSEARCH_CONTAINER" curl -s -o /dev/null -X DELETE "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}"
  docker exec "$OPENSEARCH_CONTAINER" rm -rf "$repo_location"
  rm -rf "$SNAPSHOT_ROOT/${repo_name}"

  log "OpenSearch 备份完成 (${outfile})"
}

purge_old_backups() {
  log "清理超过 ${RETENTION_DAYS} 天的历史备份"
  find "$BACKUP_ROOT" -type f -mtime +"$RETENTION_DAYS" -print -delete
}

backup_percona
backup_opensearch
purge_old_backups

log "共享层备份完成"
