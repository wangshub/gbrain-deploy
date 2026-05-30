#!/usr/bin/env bash
# cmd/backup.sh — backup database + brain data + config

load_config

BACKUP_DIR="${1:-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

if is_docker_mode; then
  [ -f .env ] && source .env

  echo "[1/3] Dumping PostgreSQL..."
  docker compose exec -T postgres \
    pg_dump -U "${POSTGRES_USER:-gbrain}" "${POSTGRES_DB:-gbrain}" \
    > "${BACKUP_PATH}/gbrain.sql"
  echo "  -> ${BACKUP_PATH}/gbrain.sql"

  echo "[2/3] Archiving brain repo..."
  docker compose run --rm -v "$(pwd)/${BACKUP_PATH}:/backup" gbrain \
    tar czf /backup/brain-repo.tar.gz -C /root .gbrain 2>/dev/null || \
    docker cp "$(docker compose ps -q gbrain):/root/.gbrain" "${BACKUP_PATH}/brain-repo" 2>/dev/null || \
    echo "  [skip] brain repo volume empty or service not running"
  echo "  -> ${BACKUP_PATH}/"

  echo "[3/3] Saving config..."
  cp .env "${BACKUP_PATH}/.env.backup"
else
  info "Backing up local deployment..."

  PG_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:]*\):.*|\1|p')
  PG_PORT_LOCAL=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
  PG_DB_LOCAL=$(echo "$DATABASE_URL" | sed -n 's|.*/\(.*\)|\1|p')

  echo "[1/3] Dumping PostgreSQL..."
  pg_dump -h "$PG_HOST" -p "$PG_PORT_LOCAL" "$PG_DB_LOCAL" > "${BACKUP_PATH}/gbrain.sql" 2>/dev/null || \
    warn "pg_dump failed (is PostgreSQL running?)"
  echo "  -> ${BACKUP_PATH}/gbrain.sql"

  echo "[2/3] Archiving brain data..."
  if [ -d "$HOME/.gbrain" ]; then
    tar czf "${BACKUP_PATH}/brain-data.tar.gz" -C "$HOME" .gbrain
    echo "  -> ${BACKUP_PATH}/brain-data.tar.gz"
  else
    echo "  [skip] $HOME/.gbrain not found"
  fi

  echo "[3/3] Saving config..."
  cp "$HOME/.gbrain-deploy/.env.local" "${BACKUP_PATH}/.env.backup"
fi

LATEST="${BACKUP_DIR}/latest"
rm -f "$LATEST"
ln -s "$BACKUP_PATH" "$LATEST"

TOTAL=$(du -sh "$BACKUP_PATH" | cut -f1)
echo ""
ok "Backup: ${BACKUP_PATH} (${TOTAL})"
echo -e "  Restore: ${BOLD}gbrain.sh restore ${BACKUP_PATH}${NC}"
