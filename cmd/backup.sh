#!/usr/bin/env bash
# cmd/backup.sh — encrypted, rotated backup (docker-only)
load_config

[ -n "${BACKUP_PASSPHRASE:-}" ] || die "BACKUP_PASSPHRASE not set in .env."

BACKUP_DIR="${1:-backups}"
KEEP="${BACKUP_KEEP:-7}"
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] Dumping PostgreSQL..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-gbrain}" "${POSTGRES_DB:-gbrain}" > "${WORK}/gbrain.sql"

echo "[2/3] Archiving brain data..."
docker compose exec -T gbrain tar czf - -C /root .gbrain > "${WORK}/brain-data.tar.gz" 2>/dev/null \
  || warn "brain data archive empty or gbrain not running"

cp .env "${WORK}/.env.backup"

echo "[3/3] Encrypting bundle..."
OUT="${BACKUP_DIR}/gbrain-${TS}.tar.enc"
tar czf - -C "$WORK" gbrain.sql brain-data.tar.gz .env.backup \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:"${BACKUP_PASSPHRASE}" -out "$OUT"

ln -sfn "gbrain-${TS}.tar.enc" "${BACKUP_DIR}/latest"

# Rotation: keep newest $KEEP
ls -1t "${BACKUP_DIR}"/gbrain-*.tar.enc 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old"
done

SIZE=$(du -h "$OUT" | cut -f1)
echo ""
ok "Backup: ${OUT} (${SIZE}, encrypted)"
echo -e "  Restore: ${BOLD}gbrain.sh restore ${OUT}${NC}"
echo -e "  ${DIM}Keeping newest ${KEEP}; off-host copy: scp ${OUT} <dest>${NC}"
