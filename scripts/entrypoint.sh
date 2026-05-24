#!/bin/sh
set -euo pipefail

# Wait for Postgres
echo "[entrypoint] Waiting for PostgreSQL..."
until pg_isready -h postgres -U "${POSTGRES_USER:-gbrain}" -q 2>/dev/null; do
  sleep 1
done
echo "[entrypoint] PostgreSQL is ready."

# Initialize gbrain if not already initialized
if [ ! -f /home/gbrain/.gbrain/config.json ]; then
  echo "[entrypoint] Initializing gbrain..."
  INIT_ARGS=""
  if [ -n "${GBRAIN_EMBEDDING_MODEL:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-model ${GBRAIN_EMBEDDING_MODEL}"
  fi
  if [ -n "${GBRAIN_EMBEDDING_DIMENSIONS:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-dimensions ${GBRAIN_EMBEDDING_DIMENSIONS}"
  fi
  gbrain init $INIT_ARGS
  echo "[entrypoint] gbrain initialized."
else
  echo "[entrypoint] gbrain already initialized, skipping init."
fi

echo "[entrypoint] Starting: gbrain $*"
exec gbrain "$@"
