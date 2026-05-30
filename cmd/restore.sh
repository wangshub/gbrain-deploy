#!/usr/bin/env bash
# cmd/restore.sh — restore from backup

load_config

BACKUP_PATH="${1:?Usage: gbrain.sh restore <backup-directory>}"
[ -f "${BACKUP_PATH}/gbrain.sql" ] || die "Not a valid backup: ${BACKUP_PATH}"

echo -e "  ${YELLOW}This will REPLACE all gbrain data.${NC}"
if ! prompt_yesno "Continue?" "N"; then
  echo "Aborted."
  exit 0
fi

if is_docker_mode; then
  [ -f .env ] && source .env

  echo "[1/3] Stopping gbrain..."
  docker compose stop gbrain

  echo "[2/3] Restoring PostgreSQL..."
  docker compose exec -T postgres \
    psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
    -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
  docker compose exec -T postgres \
    psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
    -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER:-gbrain};" 2>/dev/null || true
  docker compose exec -T postgres \
    psql -U "${POSTGRES_USER:-gbrain}" -d "${POSTGRES_DB:-gbrain}" \
    < "${BACKUP_PATH}/gbrain.sql"

  echo "[3/3] Restoring brain repo..."
  if [ -f "${BACKUP_PATH}/brain-repo.tar.gz" ]; then
    docker compose run --rm -v "$(pwd)/${BACKUP_PATH}:/backup" gbrain \
      tar xzf /backup/brain-repo.tar.gz -C /root/ 2>/dev/null || true
  fi

  echo "Starting gbrain..."
  docker compose start gbrain
else
  info "Stopping gbrain..."
  SVC_TYPE=$(detect_service_type)
  [ "$SVC_TYPE" = "systemd" ] && sudo systemctl stop gbrain 2>/dev/null || true
  [ "$SVC_TYPE" = "launchd" ] && launchctl unload ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true

  if [ -f "${BACKUP_PATH}/gbrain.sql" ]; then
    PG_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    PG_PORT_LOCAL=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    PG_DB_LOCAL=$(echo "$DATABASE_URL" | sed -n 's|.*/\(.*\)|\1|p')
    info "Restoring PostgreSQL..."
    psql -h "$PG_HOST" -p "$PG_PORT_LOCAL" -U postgres -d "$PG_DB_LOCAL" \
      -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
    psql -h "$PG_HOST" -p "$PG_PORT_LOCAL" -U postgres -d "$PG_DB_LOCAL" \
      -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER:-gbrain};" 2>/dev/null || true
    psql -h "$PG_HOST" -p "$PG_PORT_LOCAL" "${PG_DB_LOCAL}" < "${BACKUP_PATH}/gbrain.sql"
  fi

  [ -f "${BACKUP_PATH}/brain-data.tar.gz" ] && {
    info "Restoring brain data..."
    tar xzf "${BACKUP_PATH}/brain-data.tar.gz" -C "$HOME/" 2>/dev/null || true
  }

  [ -f "${BACKUP_PATH}/.env.backup" ] && {
    info "Restoring config..."
    cp "${BACKUP_PATH}/.env.backup" "$HOME/.gbrain-deploy/.env.local"
  }

  info "Starting gbrain..."
  [ "$SVC_TYPE" = "systemd" ] && sudo systemctl start gbrain
  [ "$SVC_TYPE" = "launchd" ] && launchctl load ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true
fi

echo ""
ok "Restore complete from: ${BACKUP_PATH}"
