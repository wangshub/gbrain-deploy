#!/usr/bin/env bash
# cmd/restore.sh — decrypt + restore (docker-only)
load_config

[ -n "${BACKUP_PASSPHRASE:-}" ] || die "BACKUP_PASSPHRASE not set in .env."

ENC="${1:?Usage: gbrain.sh restore <backups/gbrain-*.tar.enc>}"
[ -f "$ENC" ] || die "Backup not found: ${ENC}"

echo -e "  ${YELLOW}This will REPLACE all gbrain data.${NC}"
prompt_yesno "Continue?" "N" || { echo "Aborted."; exit 0; }

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "[1/4] Decrypting..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass pass:"${BACKUP_PASSPHRASE}" -in "$ENC" \
  | tar xzf - -C "$WORK" || die "Decrypt failed (wrong passphrase?)."
[ -f "${WORK}/gbrain.sql" ] || die "Invalid backup bundle."

echo "[2/4] Stopping gbrain..."
docker compose stop gbrain

echo "[3/4] Restoring PostgreSQL..."
docker compose exec -T postgres psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
docker compose exec -T postgres psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
  -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER:-gbrain};" 2>/dev/null || true
docker compose exec -T postgres psql -U "${POSTGRES_USER:-gbrain}" -d "${POSTGRES_DB:-gbrain}" < "${WORK}/gbrain.sql"

echo "[4/4] Restoring brain data..."
docker compose start gbrain
if [ -f "${WORK}/brain-data.tar.gz" ]; then
  # /root/.gbrain is a volume mountpoint — clear its CONTENTS (not the dir itself),
  # then extract. Surface failure instead of silently swallowing it.
  if docker compose exec -T gbrain sh -c 'find /root/.gbrain -mindepth 1 -delete 2>/dev/null; tar xzf - -C /root' < "${WORK}/brain-data.tar.gz"; then
    docker compose restart gbrain
  else
    warn "Brain data restore failed — database was restored, but brain content may be incomplete."
  fi
fi

echo ""
ok "Restore complete from: ${ENC}"
