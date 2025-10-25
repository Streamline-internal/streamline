#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 /chemin/vers/opscotch_*.sql.gz"; exit 64; }
ARCHIVE="$1"
docker compose stop opscotch
gunzip -c "${ARCHIVE}" | docker run --rm -i --network net_opscotch -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres:16-alpine \
  psql -h db -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
docker compose start opscotch
echo "[ok] Restore effectué."
