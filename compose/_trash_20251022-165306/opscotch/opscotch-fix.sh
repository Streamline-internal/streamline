#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/streamline/compose/opscotch"
COMPOSE_MAIN="$WORKDIR/docker-compose.yml"
OVERRIDE_FIX="$WORKDIR/docker-compose.override.fix.yml"
ENV_FIX="$WORKDIR/fix.env"

if [ ! -f "$COMPOSE_MAIN" ]; then
  echo "? $COMPOSE_MAIN introuvable."
  exit 1
fi

command -v openssl >/dev/null || { echo "? openssl manquant (apt-get install -y openssl)"; exit 1; }
command -v curl    >/dev/null || { echo "? curl manquant (apt-get install -y curl)"; exit 1; }

echo "== G?n?re/actualise DATA_ENCRYPTION_KEY + NEXTAUTH_SECRET =="
DATA_ENCRYPTION_KEY="$(openssl rand -base64 32)"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"

cat >"$ENV_FIX" <<'ENV'
POSTGRES_USER=opscotch
POSTGRES_PASSWORD=opscotch123
POSTGRES_DB=opscotch

BASE_URL=http://127.0.0.1:3170
APP_BASE_URL=http://127.0.0.1:3170
NEXTAUTH_URL=http://127.0.0.1:3170
VITE_BASE_URL=http://127.0.0.1:3170
VITE_BACKEND_API_URL=http://127.0.0.1:8080
PUBLIC_URL=http://127.0.0.1:3170
SITE_URL=http://127.0.0.1:3170
WHITELISTED_ORIGINS=http://127.0.0.1:3170

COOKIE_DOMAIN=localhost
SESSION_COOKIE_DOMAIN=localhost
DISABLE_SECURE_COOKIES=true
ALLOW_SECURE_COOKIES=false

DATABASE_URL=postgresql://opscotch:opscotch123@db:5432/opscotch?schema=public

PORT=8080
BACKEND_PORT=8080
WEB_PORT=3200
NODE_ENV=production
ENV

{
  echo "DATA_ENCRYPTION_KEY=$DATA_ENCRYPTION_KEY"
  echo "NEXTAUTH_SECRET=$NEXTAUTH_SECRET"
} >> "$ENV_FIX"

NEED_IMAGE=0
if ! grep -qE '^\s*image:\s*hoppscotch/'; then
  if ! grep -qE '^\s*image:\s*hoppscotch/.*hoppscotch' "$COMPOSE_MAIN"; then
    NEED_IMAGE=1
  fi
fi

echo "== (R?)?criture de $OVERRIDE_FIX =="
cat >"$OVERRIDE_FIX" <<YAML
services:
  opscotch:
    $( [ $NEED_IMAGE -eq 1 ] && echo 'image: hoppscotch/hoppscotch:latest' )
    environment:
      BASE_URL: \${BASE_URL}
      APP_BASE_URL: \${APP_BASE_URL}
      NEXTAUTH_URL: \${NEXTAUTH_URL}
      VITE_BASE_URL: \${VITE_BASE_URL}
      VITE_BACKEND_API_URL: \${VITE_BACKEND_API_URL}
      PUBLIC_URL: \${PUBLIC_URL}
      SITE_URL: \${SITE_URL}
      WHITELISTED_ORIGINS: \${WHITELISTED_ORIGINS}
      COOKIE_DOMAIN: \${COOKIE_DOMAIN}
      SESSION_COOKIE_DOMAIN: \${SESSION_COOKIE_DOMAIN}
      DISABLE_SECURE_COOKIES: \${DISABLE_SECURE_COOKIES}
      ALLOW_SECURE_COOKIES: \${ALLOW_SECURE_COOKIES}
      DATABASE_URL: \${DATABASE_URL}
      PORT: \${PORT}
      BACKEND_PORT: \${BACKEND_PORT}
      WEB_PORT: \${WEB_PORT}
      NODE_ENV: \${NODE_ENV}
      DATA_ENCRYPTION_KEY: \${DATA_ENCRYPTION_KEY}
      NEXTAUTH_SECRET: \${NEXTAUTH_SECRET}
    ports:
      - "3000:3000"
      - "3170:3170"
      - "8080:8080"
    healthcheck:
      test: ["CMD", "true"]
YAML

dc() { sudo docker compose -f "$COMPOSE_MAIN" -f "$OVERRIDE_FIX" --env-file "$ENV_FIX" "$@"; }

echo "== DOWN propre =="; dc down --remove-orphans || true
echo "== UP (db + app) =="; dc up -d

echo "== Attente DB healthy (60s max) =="
deadline=$((SECONDS+60)); okdb=0
while [ $SECONDS -lt $deadline ]; do
  if dc ps | grep -E "db\s+.*(healthy)" >/dev/null 2>&1; then okdb=1; break; fi
  sleep 2
done
[ $okdb -eq 1 ] && echo "DB OK" || echo "?? DB pas healthy (on continue)"

echo "== Seed l?ger InfraConfig (non bloquant) =="
set +e
dc exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} <<'SQL'
DO $$
BEGIN
  IF to_regclass('"InfraConfig"') IS NULL THEN
    RAISE NOTICE 'Table "InfraConfig" absente, seed ignor?.';
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
  RAISE NOTICE 'Seed ignor?: %', SQLERRM;
END $$;
SQL
set -e

echo "== Restart app =="; dc restart opscotch

BACKEND_URL="$(grep -E '^VITE_BACKEND_API_URL=' "$ENV_FIX" | cut -d= -f2)"
BASE_URL="$(grep -E '^BASE_URL=' "$ENV_FIX" | cut -d= -f2)"
: "${BACKEND_URL:=http://127.0.0.1:8080}"
: "${BASE_URL:=http://127.0.0.1:3170}"

echo "== Warmup /health (120s) =="; ok=""
for i in $(seq 1 120); do
  curl -fsS "$BACKEND_URL/health" >/dev/null 2>&1 && ok="1" && break
  sleep 1
done

echo "== Probes =="
echo "# 8080 /health:";  curl -sS  "$BACKEND_URL/health"  || true
echo "# 3170 /health:";  curl -sS  "$BASE_URL/health"     || true
echo "# 3000 (HEAD):";   curl -sSI "$BASE_URL" | head -n1 || true

echo "== Logs (2 min) =="; dc logs --since=2m --tail=200 opscotch || true

if [ -n "${ok:-}" ]; then
  echo "? OK: backend r?pond. UI: $BASE_URL"
  echo "Relance: sudo docker compose -f \"$COMPOSE_MAIN\" -f \"$OVERRIDE_FIX\" --env-file \"$ENV_FIX\" up -d"
else
  echo "?? Toujours KO. Dump \"InfraConfig\":"
  dc exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'TABLE "InfraConfig";' || true
  exit 1
fi
