#!/usr/bin/env bash
set -euo pipefail

ENV="/opt/streamline/config/.env"
if [ ! -f "$ENV" ]; then
  echo "❌ .env manquant: $ENV"
  exit 1
fi

# Charge toutes les variables du .env
set -a
source "$ENV"
set +a

if [ -z "${N8N_BASE_URL:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
  echo "❌ N8N_BASE_URL ou N8N_API_KEY manquant dans .env"
  exit 1
fi

API="$N8N_BASE_URL/rest/credentials"
AUTH="X-N8N-API-KEY: $N8N_API_KEY"
CT="Content-Type: application/json"

delete_cred_if_exists() {
  local NAME="$1"
  local TYPE="$2"

  if command -v jq >/dev/null 2>&1; then
    local ID
    ID=$(curl -s -H "$AUTH" "$API" \
      | jq -r ".data[] | select(.name==\"$NAME\" and .type==\"$TYPE\") | .id" 2>/dev/null)
    if [ -n "$ID" ] && [ "$ID" != "null" ]; then
      curl -s -X DELETE -H "$AUTH" "$API/$ID" >/dev/null || true
    fi
  fi
}

echo "👉 Création des credentials à partir du .env"

# 1️⃣ Airtable - Streamline (from ENV)
if [ -n "${AIRTABLE_API_KEY:-}" ]; then
  delete_cred_if_exists "Airtable - Streamline (from ENV)" "airtableApi"

  curl -s -X POST "$API" \
    -H "$AUTH" -H "$CT" \
    -d "{
      \"name\": \"Airtable - Streamline (from ENV)\",
      \"type\": \"airtableApi\",
      \"data\": {
        \"accessToken\": \"${AIRTABLE_API_KEY}\"
      },
      \"nodesAccess\": [
        { \"nodeType\": \"n8n-nodes-base.airtable\" }
      ]
    }" >/dev/null

  echo "✅ Airtable - Streamline (from ENV)"
else
  echo "⚠️ AIRTABLE_API_KEY manquant dans .env -> nœud Airtable ne marchera pas"
fi

# 2️⃣ Postgres - Streamline Internal
if [ -n "${POSTGRES_HOST:-}" ] && [ -n "${POSTGRES_DB:-}" ] && [ -n "${POSTGRES_USER:-}" ] && [ -n "${POSTGRES_PASSWORD:-}" ]; then
  delete_cred_if_exists "Postgres - Streamline Internal" "postgres"

  curl -s -X POST "$API" \
    -H "$AUTH" -H "$CT" \
    -d "{
      \"name\": \"Postgres - Streamline Internal\",
      \"type\": \"postgres\",
      \"data\": {
        \"user\": \"${POSTGRES_USER}\",
        \"password\": \"${POSTGRES_PASSWORD}\",
        \"database\": \"${POSTGRES_DB}\",
        \"host\": \"${POSTGRES_HOST}\",
        \"port\": \"${POSTGRES_PORT:-5432}\"
      },
      \"nodesAccess\": [
        { \"nodeType\": \"n8n-nodes-base.postgres\" }
      ]
    }" >/dev/null

  echo \"✅ Postgres - Streamline Internal\"
else
  echo \"⚠️ Variables POSTGRES_* manquantes -> nœud Postgres ne marchera pas\"
fi

echo \"✅ Bootstrap terminé\"
