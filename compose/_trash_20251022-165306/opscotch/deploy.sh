#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export COMPOSE_PROJECT_NAME="opscotch"
export DOCKER_BUILDKIT=1

# Dépendances utiles
if ! command -v jq >/dev/null 2>&1; then
  echo "Installe jq (apt-get update && apt-get install -y jq) pour le suivi health."
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Installe curl (apt-get update && apt-get install -y curl)."
fi

CUR_IMG="$(grep -E '^OPSCOTCH_IMAGE=' .env | cut -d= -f2-)"
mkdir -p .state
if docker image inspect "${CUR_IMG}" >/dev/null 2>&1; then
  docker image inspect "${CUR_IMG}" --format '{{.Id}}' > .state/PREV_IMAGE_ID || true
fi

echo "== Pull images =="
docker compose pull

echo "== Up (detached) =="
docker compose up -d

echo "== Attente 'healthy' =="
deadline=$((SECONDS+600))
healthy_json() { docker compose ps --format json 2>/dev/null || true; }
while true; do
  json="$(healthy_json)"
  [[ -n "$json" ]] || { echo "compose ps vide"; sleep 2; continue; }
  if command -v jq >/dev/null 2>&1; then
    all_ok=$(echo "$json" | jq -r 'all(.[]?.Health=="healthy")')
    [[ "$all_ok" == "true" ]] && break
  else
    # fallback sans jq : si tous les services sont "running", on continue
    running=$(docker compose ps --status running --services | wc -l)
    total=$(docker compose ps --services | wc -l)
    [[ "$running" -gt 0 && "$running" -eq "$total" ]] && break
  fi
  (( SECONDS > deadline )) && { echo "Timeout healthchecks"; docker compose ps; exit 1; }
  sleep 3
done
echo "[ok] Services healthy."

# Smoke via Caddy
source .env
set +e
echo "== Smoke (public) =="
curl -kIs "https://${API_HOST}/ping" | head -n1
curl -kIs "https://${API_HOST}/"    | head -n1
set -e
echo "[ok] Déploiement OK."
