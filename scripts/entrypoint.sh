#!/bin/sh
set -euo pipefail

# ── Wait for Postgres ────────────────────────────────
echo "[entrypoint] Waiting for PostgreSQL..."
until pg_isready -h postgres -U "${POSTGRES_USER:-gbrain}" -q 2>/dev/null; do
  sleep 1
done
echo "[entrypoint] PostgreSQL is ready."

# ── Map LLM config to gbrain env vars ───────────────
# Only set OPENAI_BASE_URL from LLM if no embedding-specific URL is already set
if [ -n "${LLM_API_BASE:-}" ] && [ -z "${OPENAI_BASE_URL:-}" ]; then
  export OPENAI_BASE_URL="${LLM_API_BASE}"
fi
if [ -n "${LLM_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  export OPENAI_API_KEY="${LLM_API_KEY}"
fi

# ── Set admin bootstrap token if strong enough ───────
# In Docker, the token arrives as GBRAIN_ADMIN_BOOTSTRAP_TOKEN (renamed by compose).
# Validate strength and warn if too weak.
_BOOTSTRAP_TOKEN="${GBRAIN_ADMIN_BOOTSTRAP_TOKEN:-}"
if [ -n "$_BOOTSTRAP_TOKEN" ]; then
  if printf '%s' "$_BOOTSTRAP_TOKEN" | grep -qE '^[A-Za-z0-9_-]{32,}$'; then
    export GBRAIN_ADMIN_BOOTSTRAP_TOKEN="$_BOOTSTRAP_TOKEN"
  else
    echo "[entrypoint] WARNING: admin secret too weak for bootstrap token (need 32+ chars, [A-Za-z0-9_-])."
    echo "[entrypoint] gbrain will auto-generate one — check logs."
    unset GBRAIN_ADMIN_BOOTSTRAP_TOKEN
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

  # Install skills (60+ skills, 9 skill packs)
  echo "[entrypoint] Installing gbrain skills..."
  gbrain install || echo "[entrypoint] Warning: gbrain install failed, some skills may be missing."
  echo "[entrypoint] Skills installed."
fi

# ── Git sync ─────────────────────────────────────────
BRAIN_DIR="/root/.gbrain"

# Initialize as git repo first (before any git config)
if [ ! -d "$BRAIN_DIR/.git" ]; then
  echo "[entrypoint] Initializing git repo in brain directory..."
  git init "$BRAIN_DIR"
fi

# Ensure git user is configured
if [ -z "$(git -C "$BRAIN_DIR" config user.name 2>/dev/null)" ]; then
  git -C "$BRAIN_DIR" config user.name "${BRAIN_GIT_USER:-gbrain}"
  git -C "$BRAIN_DIR" config user.email "${BRAIN_GIT_EMAIL:-gbrain@localhost}"
fi

# Configure remote if specified
if [ -n "${BRAIN_GIT_REMOTE:-}" ]; then
  BRANCH="${BRAIN_GIT_BRANCH:-main}"

  # Store token via git credential-store (chmod 600), never embed in remote URL
  if [ -n "${BRAIN_GIT_TOKEN:-}" ]; then
    GIT_HOST=$(echo "$BRAIN_GIT_REMOTE" | sed -n 's|https://\([^/]*\)/.*|\1|p')
    if [ -n "$GIT_HOST" ]; then
      git -C "$BRAIN_DIR" config credential.helper store
      printf 'https://%s:x-oauth-basic@%s\n' "${BRAIN_GIT_TOKEN}" "${GIT_HOST}" > /root/.git-credentials
      chmod 600 /root/.git-credentials
    fi
  fi

  if git -C "$BRAIN_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$BRAIN_DIR" remote set-url origin "$BRAIN_GIT_REMOTE"
  else
    git -C "$BRAIN_DIR" remote add origin "$BRAIN_GIT_REMOTE"
  fi

  echo "[entrypoint] Pulling brain from remote (${BRANCH})..."
  git -C "$BRAIN_DIR" fetch origin "${BRANCH}" 2>/dev/null || true
  git -C "$BRAIN_DIR" reset --hard "origin/${BRANCH}" 2>/dev/null || true
fi

echo "[entrypoint] Starting: gbrain $*"
exec gbrain "$@"
