#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
BACKUP_DIR="/opt/streamline/backups/opscotch"
mkdir -p "${BACKUP_DIR}"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
file="${BACKUP_DIR}/opscotch_${ts}.sql.gz"
echo "== Backup DB -> ${file} =="
docker run --rm --network net_opscotch -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres:16-alpine \
  pg_dump -h db -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" | gzip -9 > "${file}"
echo "[ok] Backup: ${file}"
