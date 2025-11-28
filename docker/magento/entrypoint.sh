#!/usr/bin/env bash
set -euo pipefail

MAGENTO_ROOT=${MAGENTO_ROOT:-/var/www/html}
cd "$MAGENTO_ROOT"

SENTINEL=${MAGENTO_GENERATED_SENTINEL:-generated/code/Magento/Framework/App/ResourceConnection/Proxy.php}
REGENERATE_FLAG=var/.regenerate
REGENERATE_LOCK=var/.regenerate.lock

ensure_generated() {
  if [[ "${MAGENTO_FORCE_COMPILE:-0}" == "1" ]] || [[ ! -s "$SENTINEL" ]]; then
    echo "[magento-entrypoint] Generated code missing, running setup:di:compile..."
    php bin/magento setup:di:compile
  else
    echo "[magento-entrypoint] Generated code present, skipping compilation."
  fi
}

maybe_run_setup_upgrade() {
  if [[ "${MAGENTO_RUN_SETUP_UPGRADE:-0}" == "1" ]]; then
    echo "[magento-entrypoint] Running setup:upgrade..."
    php bin/magento setup:upgrade --keep-generated
  fi
}

clear_regenerate_flag() {
  if [[ -e "$REGENERATE_FLAG" || -e "$REGENERATE_LOCK" ]]; then
    echo "[magento-entrypoint] Clearing regenerate flag..."
    rm -f "$REGENERATE_FLAG" "$REGENERATE_LOCK"
  fi
}

clear_regenerate_flag
maybe_run_setup_upgrade
ensure_generated

exec "$@"
