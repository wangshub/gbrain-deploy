#!/bin/sh
set -euo pipefail

# ── Wait for Postgres ────────────────────────────────
echo "[entrypoint] Waiting for PostgreSQL..."
until pg_isready -h postgres -U "${POSTGRES_USER:-gbrain}" -q 2>/dev/null; do
  sleep 1
done
echo "[entrypoint] PostgreSQL is ready."

# ── Map LLM config to gbrain env vars ───────────────
# If a custom LLM_API_BASE is set, expose as OPENAI_BASE_URL for
# gbrain's OpenAI-compatible SDK. Also set OPENAI_API_KEY to the
# provided key so gbrain picks it up for enrichment/extraction.
if [ -n "${LLM_API_BASE:-}" ]; then
  export OPENAI_BASE_URL="${LLM_API_BASE}"
fi
if [ -n "${LLM_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  export OPENAI_API_KEY="${LLM_API_KEY}"
fi

# ── Initialize gbrain ───────────────────────────────
if [ ! -f /home/gbrain/.gbrain/config.json ]; then
  echo "[entrypoint] Initializing gbrain..."
  INIT_ARGS=""
  if [ -n "${EMBEDDING_GBRAIN_SPEC:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-model ${EMBEDDING_GBRAIN_SPEC}"
  fi
  if [ -n "${EMBEDDING_DIM:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-dimensions ${EMBEDDING_DIM}"
  fi
  # shellcheck disable=SC2086
  gbrain init $INIT_ARGS
  echo "[entrypoint] gbrain initialized."
else
  echo "[entrypoint] gbrain already initialized, skipping init."
fi

echo "[entrypoint] Starting: gbrain $*"
exec gbrain "$@"
