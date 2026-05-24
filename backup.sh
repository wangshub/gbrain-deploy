#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
[ -f .env ] && source .env

BACKUP_DIR="${1:-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

mkdir -p "$BACKUP_PATH"

echo "[1/3] Dumping PostgreSQL..."
docker compose exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-gbrain}" "${POSTGRES_DB:-gbrain}" \
  > "${BACKUP_PATH}/gbrain.sql"
echo "  -> ${BACKUP_PATH}/gbrain.sql"

echo "[2/3] Archiving brain repo..."
docker compose run --rm -v "$(pwd)/${BACKUP_PATH}:/backup" gbrain \
  tar czf /backup/brain-repo.tar.gz -C /home/gbrain .gbrain 2>/dev/null || \
  docker cp gbrain-deploy-gbrain-1:/home/gbrain/.gbrain "${BACKUP_PATH}/brain-repo" 2>/dev/null || \
  echo "  [skip] brain repo volume empty or service not running"
echo "  -> ${BACKUP_PATH}/"

echo "[3/3] Saving config..."
cp .env "${BACKUP_PATH}/.env.backup"

LATEST="${BACKUP_DIR}/latest"
rm -f "$LATEST"
ln -s "$BACKUP_PATH" "$LATEST"

TOTAL=$(du -sh "$BACKUP_PATH" | cut -f1)
echo ""
echo "Done. Backup: ${BACKUP_PATH} (${TOTAL})"
echo "Restore: ./restore.sh ${BACKUP_PATH}"
