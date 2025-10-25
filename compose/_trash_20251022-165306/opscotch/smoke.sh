#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
echo "== /ping =="; curl -fsS -k "https://${API_HOST}/ping" | sed -n '1,2p'
echo "== / (UI) =="
code="$(curl -kIs "https://${API_HOST}/" | head -n1 | awk '{print $2}')"
[[ "$code" =~ ^(200|304|301|302)$ ]] || { echo "UI HTTP status: $code (nok)"; exit 1; }
curl -fsS -k "https://${API_HOST}/api/health" >/dev/null 2>&1 || true
echo "[ok] Smoke tests terminés."
