#!/bin/sh
set -euo pipefail

# ── Wait for Postgres ────────────────────────────────
echo "[entrypoint] Waiting for PostgreSQL..."
until pg_isready -h postgres -U "${POSTGRES_USER:-gbrain}" -q 2>/dev/null; do
  sleep 1
done
echo "[entrypoint] PostgreSQL is ready."

# ── Map LLM config to gbrain env vars ───────────────
if [ -n "${LLM_API_BASE:-}" ]; then
  export OPENAI_BASE_URL="${LLM_API_BASE}"
fi
if [ -n "${LLM_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  export OPENAI_API_KEY="${LLM_API_KEY}"
fi

# ── Set admin bootstrap token if strong enough ───────
if [ -n "${GBRAIN_ADMIN_SECRET:-}" ]; then
  if printf '%s' "${GBRAIN_ADMIN_SECRET}" | grep -qE '^[A-Za-z0-9_-]{32,}$'; then
    export GBRAIN_ADMIN_BOOTSTRAP_TOKEN="${GBRAIN_ADMIN_SECRET}"
  else
    echo "[entrypoint] GBRAIN_ADMIN_SECRET too weak for bootstrap token (need 32+ chars, [A-Za-z0-9_-])."
    echo "[entrypoint] gbrain will auto-generate one — check logs."
  fi
fi

# ── Initialize gbrain ───────────────────────────────
if [ ! -f /root/.gbrain/config.json ]; then
  echo "[entrypoint] Initializing gbrain..."
  INIT_ARGS=""
  if [ -n "${EMBEDDING_GBRAIN_SPEC:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-model ${EMBEDDING_GBRAIN_SPEC}"
  fi
  if [ -n "${EMBEDDING_DIM:-}" ]; then
    INIT_ARGS="$INIT_ARGS --embedding-dimensions ${EMBEDDING_DIM}"
  fi
  if [ -z "${EMBEDDING_GBRAIN_SPEC:-}" ] && [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${ZEROENTROPY_API_KEY:-}" ] && [ -z "${VOYAGE_API_KEY:-}" ]; then
    INIT_ARGS="$INIT_ARGS --no-embedding"
  fi
  # shellcheck disable=SC2086
  gbrain init $INIT_ARGS
  echo "[entrypoint] gbrain initialized."
else
  echo "[entrypoint] gbrain already initialized, skipping init."
fi

echo "[entrypoint] Starting: gbrain $*"
exec gbrain "$@"
