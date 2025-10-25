#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
export COMPOSE_PROJECT_NAME="opscotch"

echo "== Rollback =="
if [[ ! -f ".state/PREV_IMAGE_ID" ]]; then
  echo "Aucun PREV_IMAGE_ID trouvé." >&2; exit 2
fi
PREV_ID="$(cat .state/PREV_IMAGE_ID)"
docker image inspect "${PREV_ID}" >/dev/null 2>&1 || { echo "Image précédente absente"; exit 3; }
docker tag "${PREV_ID}" "${OPSCOTCH_IMAGE}"

docker compose down
docker compose up -d

deadline=$((SECONDS+600))
while true; do
  json="$(docker compose ps --format json 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1; then
    all_ok=$(echo "$json" | jq -r 'all(.[]?.Health=="healthy")')
    [[ "$all_ok" == "true" ]] && break
  else
    running=$(docker compose ps --status running --services | wc -l)
    total=$(docker compose ps --services | wc -l)
    [[ "$running" -gt 0 && "$running" -eq "$total" ]] && break
  fi
  (( SECONDS > deadline )) && { echo "Timeout healthchecks"; docker compose ps; exit 1; }
  sleep 3
done
echo "[ok] Rollback OK."
