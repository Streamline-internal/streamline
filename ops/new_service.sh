#!/usr/bin/env bash
set -euo pipefail
ROOT=/opt/streamline
ENV="$ROOT/config/.env"
[ -f "$ENV" ] || { echo "Missing $ENV"; exit 1; }
set -o allexport; source "$ENV"; set +o allexport
[ $# -ge 4 ] || { echo "Usage: $0 <service> <image> <internal-port> <subdomain> [env-file]"; exit 1; }
SERVICE="$1"; IMAGE="$2"; INTERNAL_PORT="$3"; SUB="$4"; ENVFILE="${5:-}"
APP_DIR="$ROOT/compose/$SERVICE"; DATA_DIR="$ROOT/data/$SERVICE"
mkdir -p "$APP_DIR" "$DATA_DIR"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
{
  echo "services:"
  echo "  $SERVICE:"
  echo "    image: $IMAGE"
  [ -n "$ENVFILE" ] && echo "    env_file: [ \"$ENVFILE\" ]"
  echo "    volumes: [ \"$DATA_DIR:/data\" ]"
  echo "    labels:"
  echo "      traefik.enable: \"true\""
  echo "      traefik.http.routers.${SERVICE}-https.entrypoints: websecure"
  echo "      traefik.http.routers.${SERVICE}-https.rule: Host(\`${SUB}.${STREAMLINE_DOMAIN}\`)"
  echo "      traefik.http.routers.${SERVICE}-https.tls: \"true\""
  echo "      traefik.http.services.${SERVICE}.loadbalancer.server.port: \"$INTERNAL_PORT\""
  echo "      traefik.http.routers.${SERVICE}-http.entrypoints: web"
  echo "      traefik.http.routers.${SERVICE}-http.rule: Host(\`${SUB}.${STREAMLINE_DOMAIN}\`)"
  echo "      traefik.http.routers.${SERVICE}-http.middlewares: redirect-https"
  echo "      traefik.http.middlewares.redirect-https.redirectscheme.scheme: https"
  echo "      traefik.http.middlewares.redirect-https.redirectscheme.permanent: \"true\""
  echo "    networks: [ \"web\" ]"
  echo "    restart: always"
  echo "networks:"; echo "  web:"; echo "    external: true"
} > "$COMPOSE_FILE"
echo "Created: $COMPOSE_FILE"
echo "Data dir: $DATA_DIR"
echo "Start with: docker compose -f $COMPOSE_FILE up -d"
