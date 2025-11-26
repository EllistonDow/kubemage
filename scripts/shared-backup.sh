#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/artifacts/shared-backups}"
SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-$ROOT_DIR/artifacts/opensearch-snapshots}"
BACKEND="${SHARED_BACKEND:-k8s}" # k8s | docker
PERCONA_CONTAINER="${PERCONA_CONTAINER:-percona}"
PERCONA_NAMESPACE="${PERCONA_NAMESPACE:-databases}"
PERCONA_SELECTOR="${PERCONA_SELECTOR:-app=percona}"
PERCONA_POD="${PERCONA_POD:-}"
OPENSEARCH_CONTAINER="${OPENSEARCH_CONTAINER:-opensearch}"
OPENSEARCH_NAMESPACE="${OPENSEARCH_NAMESPACE:-search}"
OPENSEARCH_SELECTOR="${OPENSEARCH_SELECTOR:-app=opensearch}"
OPENSEARCH_POD="${OPENSEARCH_POD:-}"
OPENSEARCH_ENDPOINT="${OPENSEARCH_ENDPOINT:-http://127.0.0.1:9200}"
PERCONA_ROOT_PASSWORD="${PERCONA_ROOT_PASSWORD:-PerconaRoot!2025}"
PERCONA_K8S_CONTAINER="${PERCONA_K8S_CONTAINER:-}"
OPENSEARCH_K8S_CONTAINER="${OPENSEARCH_K8S_CONTAINER:-}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_ROOT/percona" "$BACKUP_ROOT/opensearch" "$SNAPSHOT_ROOT"

log() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"
}

select_k8s_pod() {
  local ns="$1" selector="$2"
  kubectl get pods -n "$ns" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

prepare_targets() {
  if [[ "$BACKEND" == "docker" ]]; then
    if ! docker ps --format '{{.Names}}' | grep -qx "$PERCONA_CONTAINER"; then
      log "ERROR: container '$PERCONA_CONTAINER' 不存在或未运行"
      exit 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$OPENSEARCH_CONTAINER"; then
      log "ERROR: container '$OPENSEARCH_CONTAINER' 不存在或未运行"
      exit 1
    fi
  else
    if [[ -z "$PERCONA_POD" ]]; then
      PERCONA_POD="$(select_k8s_pod "$PERCONA_NAMESPACE" "$PERCONA_SELECTOR")"
    fi
    if [[ -z "$PERCONA_POD" ]]; then
      log "ERROR: 无法在 namespace=$PERCONA_NAMESPACE 通过 selector '$PERCONA_SELECTOR' 找到 Percona Pod"
      exit 1
    fi
    if [[ -z "$OPENSEARCH_POD" ]]; then
      OPENSEARCH_POD="$(select_k8s_pod "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_SELECTOR")"
    fi
    if [[ -z "$OPENSEARCH_POD" ]]; then
      log "ERROR: 无法在 namespace=$OPENSEARCH_NAMESPACE 通过 selector '$OPENSEARCH_SELECTOR' 找到 OpenSearch Pod"
      exit 1
    fi
  fi
}

backup_percona() {
  local outfile="$BACKUP_ROOT/percona/percona_${TIMESTAMP}.sql.gz"
  log "开始备份 Percona → $outfile"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$PERCONA_CONTAINER" sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysqldump -uroot --single-transaction --quick --routines --events --triggers --all-databases"
  else
    if [[ -n "$PERCONA_K8S_CONTAINER" ]]; then
      kubectl exec -n "$PERCONA_NAMESPACE" "$PERCONA_POD" -c "$PERCONA_K8S_CONTAINER" -- sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysqldump -uroot --single-transaction --quick --routines --events --triggers --all-databases"
    else
      kubectl exec -n "$PERCONA_NAMESPACE" "$PERCONA_POD" -- sh -c "MYSQL_PWD='$PERCONA_ROOT_PASSWORD' mysqldump -uroot --single-transaction --quick --routines --events --triggers --all-databases"
    fi
  fi | gzip -c >"$outfile"
  log "Percona 备份完成 (${outfile})"
}

backup_opensearch_data_dir() {
  local outfile="$1"
  log "直接打包 OpenSearch 数据目录 → $outfile"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$OPENSEARCH_CONTAINER" tar -C /usr/share/opensearch/data -cf - . | gzip -c >"$outfile"
  else
    kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- tar -C /usr/share/opensearch/data -cf - . | gzip -c >"$outfile"
  fi
  log "OpenSearch 数据目录备份完成 (${outfile})"
}

backup_opensearch() {
  local repo_name="snap_${TIMESTAMP}"
  local repo_location="/usr/share/opensearch/snapshots/${repo_name}"
  local outfile="$BACKUP_ROOT/opensearch/opensearch_${TIMESTAMP}.tar.gz"

  log "准备 OpenSearch 快照仓库 ${repo_name}"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$OPENSEARCH_CONTAINER" mkdir -p "$repo_location"
    docker exec "$OPENSEARCH_CONTAINER" chmod 0777 "$repo_location"
  else
    if [[ -n "$OPENSEARCH_K8S_CONTAINER" ]]; then
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- mkdir -p "$repo_location"
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- chmod 0777 "$repo_location"
    else
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- mkdir -p "$repo_location"
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- chmod 0777 "$repo_location"
    fi
  fi

  local register_payload
  register_payload=$(cat <<JSON
{"type":"fs","settings":{"location":"${repo_location}","compress":true}}
JSON
)

  local register_code
  if [[ "$BACKEND" == "docker" ]]; then
    register_code=$(printf '%s' "$register_payload" | docker exec -i "$OPENSEARCH_CONTAINER" curl -s -o /dev/null -w "%{http_code}" -X PUT \
      "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}" \
      -H 'Content-Type: application/json' --data-binary @-)
  else
    register_code=$(printf '%s' "$register_payload" | kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- curl -s -o /dev/null -w "%{http_code}" -X PUT \
      "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}" \
      -H 'Content-Type: application/json' --data-binary @-)
  fi

  if [[ "$register_code" != "200" && "$register_code" != "201" ]]; then
    log "WARNING: 注册 OpenSearch 仓库失败 (HTTP $register_code)，改为打包 data 目录"
    backup_opensearch_data_dir "$outfile"
    return
  fi

  log "创建 OpenSearch 快照 ${repo_name}/full"
  local snapshot_payload='{"indices":"*","ignore_unavailable":true,"include_global_state":true}'
  local snapshot_response
  if [[ "$BACKEND" == "docker" ]]; then
    snapshot_response=$(printf '%s' "$snapshot_payload" | docker exec -i "$OPENSEARCH_CONTAINER" curl -s -w "\n%{http_code}" -X PUT \
      "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}/full?wait_for_completion=true" \
      -H 'Content-Type: application/json' --data-binary @-)
  else
    if [[ -n "$OPENSEARCH_K8S_CONTAINER" ]]; then
      snapshot_response=$(printf '%s' "$snapshot_payload" | kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- curl -s -w "\n%{http_code}" -X PUT \
      "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}/full?wait_for_completion=true" \
      -H 'Content-Type: application/json' --data-binary @-)
    else
      snapshot_response=$(printf '%s' "$snapshot_payload" | kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- curl -s -w "\n%{http_code}" -X PUT \
      "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}/full?wait_for_completion=true" \
      -H 'Content-Type: application/json' --data-binary @-)
    fi
  fi
  local snapshot_code
  snapshot_code=$(printf '%s' "$snapshot_response" | tail -n1)
  local snapshot_body
  snapshot_body=$(printf '%s' "$snapshot_response" | sed '$d')

  if [[ "$snapshot_code" != "200" && "$snapshot_code" != "201" ]]; then
    log "ERROR: 创建快照失败，详情：$snapshot_body"
    exit 1
  fi

  log "打包 OpenSearch 快照 → $outfile"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$OPENSEARCH_CONTAINER" tar -C /usr/share/opensearch/snapshots -cf - "$repo_name" | gzip -c >"$outfile"
  else
    if [[ -n "$OPENSEARCH_K8S_CONTAINER" ]]; then
      kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- tar -C /usr/share/opensearch/snapshots -cf - "$repo_name" | gzip -c >"$outfile"
    else
      kubectl exec -i -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- tar -C /usr/share/opensearch/snapshots -cf - "$repo_name" | gzip -c >"$outfile"
    fi
  fi

  log "清理临时快照仓库"
  if [[ "$BACKEND" == "docker" ]]; then
    docker exec "$OPENSEARCH_CONTAINER" curl -s -o /dev/null -X DELETE "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}"
    docker exec "$OPENSEARCH_CONTAINER" rm -rf "$repo_location"
  else
    if [[ -n "$OPENSEARCH_K8S_CONTAINER" ]]; then
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- curl -s -o /dev/null -X DELETE "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}"
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -c "$OPENSEARCH_K8S_CONTAINER" -- rm -rf "$repo_location"
    else
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- curl -s -o /dev/null -X DELETE "$OPENSEARCH_ENDPOINT/_snapshot/${repo_name}"
      kubectl exec -n "$OPENSEARCH_NAMESPACE" "$OPENSEARCH_POD" -- rm -rf "$repo_location"
    fi
  fi

  log "OpenSearch 备份完成 (${outfile})"
}

purge_old_backups() {
  log "清理超过 ${RETENTION_DAYS} 天的历史备份"
  find "$BACKUP_ROOT" -type f -mtime +"$RETENTION_DAYS" -print -delete
}

prepare_targets
backup_percona
backup_opensearch
purge_old_backups

log "共享层备份完成"
