#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# 0) Réglages "connus bons"
# =========================
STACK_DIR="/opt/streamline/compose/opscotch-clean"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
ENV_FILE="$STACK_DIR/.env"
LOG_FILE="$STACK_DIR/bootstrap.log"
NETWORK_NAME="net_opscotch"
PROJECT_NAME="opscotch"

# Images stables
IMG_APP="hoppscotch/hoppscotch:latest"
IMG_DB="postgres:15-alpine"

# Ports exposés
PORT_UI=3000         # UI statique
PORT_PROXY=3170      # Caddy (admin/ui → backend)
PORT_BACKEND=8080    # Backend direct

# DB (projet dédié)
PG_USER="opscotch"
PG_PASS="opscotch123"
PG_DB="opscotch"
PG_VOL="${PROJECT_NAME}_pgdata"

# ================================
# 1) Préparation & log persistent
# ================================
sudo mkdir -p "$STACK_DIR"
sudo chown "$USER":"$USER" "$STACK_DIR"

TMPLOG="$(mktemp)"
exec > >(tee -a "$TMPLOG") 2>&1

echo "== Purge complète de l'ancien stack (si présent) =="
set +e
sudo docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null
sudo docker network rm "$NETWORK_NAME" 2>/dev/null
sudo docker volume rm "$PG_VOL" 2>/dev/null
set -e

echo "== Vérifs =="
command -v docker >/dev/null || { echo "❌ docker manquant"; exit 1; }
command -v openssl >/dev/null || { echo "❌ openssl manquant (sudo apt-get install -y openssl)"; exit 1; }
command -v curl    >/dev/null || { echo "❌ curl manquant (sudo apt-get install -y curl)"; exit 1; }

echo "== Génération secrets (AES-256 hex64, évite Invalid key length) =="
DATA_ENCRYPTION_KEY="$(openssl rand -hex 32)"
NEXTAUTH_SECRET="$(openssl rand -hex 32)"

echo "== Écriture ENV =="
cat > "$ENV_FILE" <<EOF
POSTGRES_USER=$PG_USER
POSTGRES_PASSWORD=$PG_PASS
POSTGRES_DB=$PG_DB

BASE_URL=http://127.0.0.1:$PORT_PROXY
APP_BASE_URL=http://127.0.0.1:$PORT_PROXY
NEXTAUTH_URL=http://127.0.0.1:$PORT_PROXY
VITE_BASE_URL=http://127.0.0.1:$PORT_PROXY
VITE_BACKEND_API_URL=http://127.0.0.1:$PORT_BACKEND
PUBLIC_URL=http://127.0.0.1:$PORT_PROXY
SITE_URL=http://127.0.0.1:$PORT_PROXY
WHITELISTED_ORIGINS=http://127.0.0.1:$PORT_PROXY

COOKIE_DOMAIN=localhost
SESSION_COOKIE_DOMAIN=localhost
DISABLE_SECURE_COOKIES=true
ALLOW_SECURE_COOKIES=false

DATABASE_URL=postgresql://$PG_USER:$PG_PASS@db:5432/$PG_DB?schema=public

PORT=$PORT_BACKEND
BACKEND_PORT=$PORT_BACKEND
WEB_PORT=3200
NODE_ENV=production

DATA_ENCRYPTION_KEY=$DATA_ENCRYPTION_KEY
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
EOF

echo "== Compose autonome (app + db) =="
cat > "$COMPOSE_FILE" <<'YAML'
services:
  db:
    image: ${IMG_DB:-postgres:15-alpine}
    container_name: opscotch-db-1
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 2s
      timeout: 3s
      retries: 30
    networks:
      - net_opscotch
    volumes:
      - ${PROJECT_NAME}_pgdata:/var/lib/postgresql/data

  opscotch:
    image: ${IMG_APP:-hoppscotch/hoppscotch:latest}
    container_name: opscotch-opscotch-1
    depends_on:
      db:
        condition: service_healthy
    environment:
      BASE_URL: ${BASE_URL}
      APP_BASE_URL: ${APP_BASE_URL}
      NEXTAUTH_URL: ${NEXTAUTH_URL}
      VITE_BASE_URL: ${VITE_BASE_URL}
      VITE_BACKEND_API_URL: ${VITE_BACKEND_API_URL}
      PUBLIC_URL: ${PUBLIC_URL}
      SITE_URL: ${SITE_URL}
      WHITELISTED_ORIGINS: ${WHITELISTED_ORIGINS}
      COOKIE_DOMAIN: ${COOKIE_DOMAIN}
      SESSION_COOKIE_DOMAIN: ${SESSION_COOKIE_DOMAIN}
      DISABLE_SECURE_COOKIES: ${DISABLE_SECURE_COOKIES}
      ALLOW_SECURE_COOKIES: ${ALLOW_SECURE_COOKIES}
      DATABASE_URL: ${DATABASE_URL}
      PORT: ${PORT}
      BACKEND_PORT: ${BACKEND_PORT}
      WEB_PORT: ${WEB_PORT}
      NODE_ENV: ${NODE_ENV}
      DATA_ENCRYPTION_KEY: ${DATA_ENCRYPTION_KEY}
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
    ports:
      - "3000:3000"         # UI
      - "3170:3170"         # Reverse proxy
      - "8080:8080"         # Backend direct
    healthcheck:
      test: ["CMD", "true"] # neutralisé pendant le boot
    networks:
      - net_opscotch
    restart: unless-stopped

networks:
  net_opscotch:
    name: net_opscotch

volumes:
  ${PROJECT_NAME}_pgdata:
YAML

# var-subst pour le YAML (compose lit env du shell pour IMG_* / PROJECT_NAME)
export IMG_APP IMG_DB PROJECT_NAME

dc() { sudo docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

echo "== UP (db + app) =="
dc up -d

echo "== Attente DB healthy (≤90s) =="
deadline=$((SECONDS+90)); okdb=0
while [ $SECONDS -lt $deadline ]; do
  if dc ps | grep -E "db\s+.*(healthy)" >/dev/null 2>&1; then okdb=1; break; fi
  sleep 2
done
[ $okdb -eq 1 ] && echo "DB OK" || { echo "❌ DB pas healthy"; dc logs --since=2m db || true; exit 1; }

echo "== Seed minimal InfraConfig (non bloquant) =="
set +e
dc exec -T db psql -U "$PG_USER" -d "$PG_DB" <<'SQL'
DO $$
BEGIN
  IF to_regclass('"InfraConfig"') IS NULL THEN
    RAISE NOTICE 'Table "InfraConfig" absente; seed ignoré.';
    RETURN;
  END IF;

  INSERT INTO "InfraConfig"(id,name,value,"createdOn","updatedOn","isEncrypted")
  VALUES (md5('VITE_BASE_URL'),'VITE_BASE_URL','http://127.0.0.1:3170',NOW(),NOW(),false)
  ON CONFLICT (name) DO UPDATE SET value=EXCLUDED.value,"updatedOn"=NOW();

  INSERT INTO "InfraConfig"(id,name,value,"createdOn","updatedOn","isEncrypted")
  VALUES (md5('VITE_BACKEND_API_URL'),'VITE_BACKEND_API_URL','http://127.0.0.1:8080',NOW(),NOW(),false)
  ON CONFLICT (name) DO UPDATE SET value=EXCLUDED.value,"updatedOn"=NOW();

  INSERT INTO "InfraConfig"(id,name,value,"createdOn","updatedOn","isEncrypted")
  VALUES (md5('ALLOW_SECURE_COOKIES'),'ALLOW_SECURE_COOKIES','false',NOW(),NOW(),false)
  ON CONFLICT (name) DO UPDATE SET value=EXCLUDED.value,"updatedOn"=NOW();
EXCEPTION WHEN others THEN
  RAISE NOTICE 'Seed ignoré: %', SQLERRM;
END $$;
SQL
set -e

echo "== Restart app pour relire la conf =="
dc restart opscotch

BACKEND_URL="http://127.0.0.1:${PORT_BACKEND}"
BASE_URL="http://127.0.0.1:${PORT_PROXY}"

echo "== Warmup backend (≤120s) =="
ok=""
for i in $(seq 1 120); do
  if curl -fsS "${BACKEND_URL}/health" >/dev/null 2>&1; then ok="1"; break; fi
  sleep 1
done

echo "== Probes =="
echo "# ${PORT_BACKEND} /health:";  curl -sS  "${BACKEND_URL}/health"  || true
echo "# ${PORT_PROXY} /health:";    curl -sS  "${BASE_URL}/health"     || true
echo "# HEAD ${PORT_PROXY} (UI):";  curl -sSI "${BASE_URL}" | head -n1 || true

echo "== Logs récents (2 min) =="
dc logs --since=2m --tail=300 opscotch || true

# Sauvegarde du log d'exécution
if ! mv "$TMPLOG" "$LOG_FILE" 2>/dev/null; then
  sudo mv "$TMPLOG" "$LOG_FILE"
  sudo chown "$USER":"$USER" "$LOG_FILE"
fi
echo "📄 Log: $LOG_FILE"

if [ -n "${ok:-}" ]; then
  echo "✅ OK: backend répond → UI: ${BASE_URL}"
  echo "Relance: sudo docker compose -p \"$PROJECT_NAME\" -f \"$COMPOSE_FILE\" --env-file \"$ENV_FILE\" up -d"
else
  echo "⚠️ Backend KO → dump InfraConfig:"
  set +e
  dc exec -T db psql -U "$PG_USER" -d "$PG_DB" -c 'TABLE "InfraConfig";' || true
  set -e
  exit 1
fi
