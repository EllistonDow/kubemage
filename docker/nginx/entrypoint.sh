#!/usr/bin/env bash
set -euo pipefail

RUNTIME_SNIPPET="/etc/nginx/snippets/pagespeed-runtime.conf"
HTTP_RUNTIME_SNIPPET="/etc/nginx/snippets/pagespeed-http-runtime.conf"
DISABLE_MSG="# ngx_pagespeed disabled via NGX_PAGESPEED=off"

mkdir -p "$(dirname "$RUNTIME_SNIPPET")"
mkdir -p "$(dirname "$HTTP_RUNTIME_SNIPPET")"

if [[ "${NGX_PAGESPEED:-on}" == "off" ]]; then
  echo "$DISABLE_MSG" > "$RUNTIME_SNIPPET"
  echo "$DISABLE_MSG" > "$HTTP_RUNTIME_SNIPPET"
else
  echo "include /etc/nginx/snippets/pagespeed.conf;" > "$RUNTIME_SNIPPET"
  echo "include /etc/nginx/snippets/pagespeed-http.conf;" > "$HTTP_RUNTIME_SNIPPET"
fi

exec nginx -g "daemon off;"
