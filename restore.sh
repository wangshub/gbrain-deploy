#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

BACKUP_PATH="${1:?Usage: restore.sh <backup-directory>}"
[ -f "${BACKUP_PATH}/gbrain.sql" ] || { echo "Not a valid backup: ${BACKUP_PATH}"; exit 1; }

echo "This will REPLACE all gbrain data. Are you sure? [y/N]"
read -r confirm
[ "$confirm" = "y" ] || { echo "Aborted."; exit 0; }

[ -f .env ] && source .env

echo "[1/3] Stopping gbrain..."
docker compose stop gbrain

echo "[2/3] Restoring PostgreSQL..."
# Drop and recreate to ensure clean state
docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-gbrain}" -d "${POSTGRES_DB:-gbrain}" \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
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

echo ""
echo "Restore complete from: ${BACKUP_PATH}"
