#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_FILE="$ROOT_DIR/scripts/pagespeed.lhci.config.js"
CHROME_CACHE_ROOT="${PAGESPEED_CHROME_CACHE:-$ROOT_DIR/.cache/pagespeed}"
METHOD="${PAGESPEED_METHOD:-psi}"

if [[ "${PAGESPEED_ENABLED:-false}" != "true" ]]; then
  echo "[pagespeed] Disabled (set PAGESPEED_ENABLED=true to run)."
  exit 0
fi

if [[ ! -s "$CONFIG_FILE" ]]; then
  echo "[pagespeed] Missing config file at $CONFIG_FILE" >&2
  exit 1
fi

if [[ -z "${PAGESPEED_URLS:-}" ]]; then
  echo "[pagespeed] PAGESPEED_URLS is required (space or newline separated list of URLs)." >&2
  exit 1
fi

if [[ "$METHOD" != "psi" && "$METHOD" != "node" ]]; then
  echo "[pagespeed] Unsupported method '$METHOD'. Use 'psi' or 'node'." >&2
  exit 1
fi

command -v node >/dev/null 2>&1 || {
  echo "[pagespeed] Node.js (for npx) is required." >&2
  exit 1
}

ensure_chrome() {
  if [[ -n "${PAGESPEED_CHROME_PATH:-}" && -x "${PAGESPEED_CHROME_PATH}" ]]; then
    echo "$PAGESPEED_CHROME_PATH"
    return 0
  fi

  local cached
  if [[ -d "$CHROME_CACHE_ROOT" ]]; then
    cached=$(find "$CHROME_CACHE_ROOT" -type f -path '*chrome-linux64/chrome' 2>/dev/null | sort | head -n 1 || true)
    if [[ -n "$cached" ]]; then
      echo "$cached"
      return 0
    fi
  fi

  mkdir -p "$CHROME_CACHE_ROOT"
  echo "[pagespeed] Chrome binary not found, downloading via @puppeteer/browsers..."
  npx --yes @puppeteer/browsers@1.9.1 install chrome@stable --path "$CHROME_CACHE_ROOT"

  cached=$(find "$CHROME_CACHE_ROOT" -type f -path '*chrome-linux64/chrome' 2>/dev/null | sort | head -n 1 || true)
  if [[ -z "$cached" ]]; then
    echo "[pagespeed] Unable to locate Chrome binary after download." >&2
    exit 1
  fi

  echo "$cached"
}

OUTPUT_ROOT="$ROOT_DIR/${PAGESPEED_OUTPUT_DIR:-artifacts/pagespeed}"
RUN_ID=$(date -u +%Y%m%d-%H%M%SZ)
OUTPUT_DIR="$OUTPUT_ROOT/$RUN_ID"
mkdir -p "$OUTPUT_DIR"

printf -v LHCI_URLS '%s' "${PAGESPEED_URLS}"
export LHCI_URLS
export LHCI_RUNS=${PAGESPEED_RUNS:-3}
export PAGESPEED_LH_PRESET=${PAGESPEED_PRESET:-desktop}
export PAGESPEED_LH_CHROME_FLAGS=${PAGESPEED_CHROME_FLAGS:---no-sandbox --disable-dev-shm-usage}
export LHCI_MIN_SCORE=${PAGESPEED_MIN_SCORE:-0.65}
export LHCI_A11Y_MIN_SCORE=${PAGESPEED_A11Y_MIN_SCORE:-0.8}
export LHCI_BP_MIN_SCORE=${PAGESPEED_BP_MIN_SCORE:-0.85}
export LHCI_SEO_MIN_SCORE=${PAGESPEED_SEO_MIN_SCORE:-0.9}
export LHCI_OUTPUT_DIR="$OUTPUT_DIR"
export LHCI_METHOD="$METHOD"

if [[ "$METHOD" == "psi" ]]; then
  export LHCI_PSI_STRATEGY=${PAGESPEED_PSI_STRATEGY:-mobile}
  if [[ -n "${PAGESPEED_PSI_API_KEY:-}" ]]; then
    export LHCI_PSI_API_KEY="$PAGESPEED_PSI_API_KEY"
  fi
else
  CHROME_PATH=$(ensure_chrome)
  export LHCI_CHROME_PATH="$CHROME_PATH"
fi

LHCI_VERSION=${PAGESPEED_LHCI_VERSION:-0.13.0}

set -x
npx --yes "@lhci/cli@${LHCI_VERSION}" autorun --config="$CONFIG_FILE"
set +x

echo "[pagespeed] Reports saved to $OUTPUT_DIR"
