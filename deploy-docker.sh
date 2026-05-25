#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# ── Colors ───────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "${CYAN}  >${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}  !${NC} $*"; }
die()   { echo -e "${RED}  ✗${NC} $*" >&2; exit 1; }

header() {
  echo ""
  echo -e "${BOLD}━━━ $1 ━━━${NC}"
  echo ""
}

# ── Prompt helpers ──────────────────────────────────
prompt_text() {
  local label="$1" default="${2:-}"
  if [ -n "$default" ]; then
    echo -ne "  ${label} ${DIM}[${default}]:${NC} "
  else
    echo -ne "  ${label}: "
  fi
  read -r val
  echo "${val:-$default}"
}

prompt_password() {
  local label="$1"
  echo -ne "  ${label}: "
  read -rs val
  echo ""
  echo "$val"
}

prompt_select() {
  local label="$1"; shift
  local i=1
  echo ""
  echo -e "  ${label}"
  for opt in "$@"; do
    echo -e "    ${BOLD}${i})${NC} ${opt}"
    i=$((i + 1))
  done
  echo -ne "  ${CYAN}Select [1]:${NC} "
  read -r choice
  local idx="${choice:-1}"
  echo "$idx"
}

prompt_yesno() {
  local label="$1" default="${2:-Y}"
  local hint="[Y/n]"
  [ "$default" = "N" ] && hint="[y/N]"
  echo -ne "  ${label} ${DIM}${hint}:${NC} "
  read -r val
  val="${val:-$default}"
  [[ "$val" =~ ^[Yy] ]]
}

gen_secret() { openssl rand -base64 24 | tr -d '/+=' | head -c 32; }

# ── Prerequisites ───────────────────────────────────
command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is not available."

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     gbrain Central Deployment Setup      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

# ══════════════════════════════════════════════════════
# Step 1: Database
# ══════════════════════════════════════════════════════
header "Step 1/4: Database"

PG_PASS_DEFAULT=$(gen_secret)
PG_PASS=$(prompt_text "PostgreSQL password" "[auto-generated]")
PG_PASS="${PG_PASS:-$PG_PASS_DEFAULT}"
[ "$PG_PASS" = "[auto-generated]" ] && PG_PASS="$PG_PASS_DEFAULT"

PG_USER=$(prompt_text "PostgreSQL user" "gbrain")
PG_DB=$(prompt_text "PostgreSQL database" "gbrain")

ok "Database: ${PG_USER}@localhost/${PG_DB}"

# ══════════════════════════════════════════════════════
# Step 2: AI Model (LLM)
# ══════════════════════════════════════════════════════
header "Step 2/4: AI Model (for enrichment, extraction, synthesis)"

LLM_CHOICE=$(prompt_select "LLM Provider:" \
  "OpenAI (api.openai.com)" \
  "OpenAI-compatible (custom URL)" \
  "Skip — configure later" \
)

case "$LLM_CHOICE" in
  1)
    LLM_API_BASE="https://api.openai.com/v1"
    LLM_API_KEY=$(prompt_password "OpenAI API Key (sk-...)")
    LLM_MODEL=$(prompt_text "Model" "gpt-4o")
    LLM_PROVIDER="openai"
    ;;
  2)
    LLM_API_BASE=$(prompt_text "API Base URL" "https://api.your-provider.com/v1")
    LLM_API_KEY=$(prompt_password "API Key")
    LLM_MODEL=$(prompt_text "Model name" "gpt-4o")
    LLM_PROVIDER="custom"
    ;;
  3)
    LLM_API_BASE=""
    LLM_API_KEY=""
    LLM_MODEL=""
    LLM_PROVIDER="skip"
    warn "LLM not configured. Enrichment/extraction features won't work until configured."
    ;;
esac

if [ "$LLM_PROVIDER" != "skip" ]; then
  ok "LLM: ${LLM_MODEL} via ${LLM_API_BASE}"
fi

# ══════════════════════════════════════════════════════
# Step 3: Embedding Model
# ══════════════════════════════════════════════════════
header "Step 3/4: Embedding Model (for vector search)"

EMBED_CHOICE=$(prompt_select "Embedding Provider:" \
  "OpenAI" \
  "OpenAI-compatible (custom URL)" \
  "ZeroEntropy" \
  "Voyage AI" \
  "Ollama (local, runs in Docker)" \
  "Ollama (connect to host)" \
  "Skip — configure later" \
)

case "$EMBED_CHOICE" in
  1)
    EMBED_API_KEY=$(prompt_password "OpenAI API Key (sk-...)")
    EMBED_MODEL=$(prompt_text "Embedding model" "text-embedding-3-small")
    EMBED_DIM=$(prompt_text "Dimensions" "1536")
    EMBED_PROVIDER="openai"
    EMBED_GBRAIN_SPEC="openai:${EMBED_MODEL}"
    ;;
  2)
    EMBED_API_BASE=$(prompt_text "Embedding API Base URL" "https://api.your-provider.com/v1")
    EMBED_API_KEY=$(prompt_password "API Key")
    EMBED_MODEL=$(prompt_text "Model name" "text-embedding-3-small")
    EMBED_DIM=$(prompt_text "Dimensions" "1536")
    EMBED_PROVIDER="custom"
    EMBED_GBRAIN_SPEC="openai:${EMBED_MODEL}"
    ;;
  3)
    EMBED_API_KEY=$(prompt_password "ZeroEntropy API Key")
    EMBED_MODEL=$(prompt_text "Embedding model" "zembed-1")
    EMBED_DIM=$(prompt_text "Dimensions" "1280")
    EMBED_PROVIDER="zeroentropy"
    EMBED_GBRAIN_SPEC="zeroentropy:${EMBED_MODEL}"
    ;;
  4)
    EMBED_API_KEY=$(prompt_password "Voyage API Key")
    EMBED_MODEL=$(prompt_text "Embedding model" "voyage-3")
    EMBED_DIM=$(prompt_text "Dimensions" "1024")
    EMBED_PROVIDER="voyage"
    EMBED_GBRAIN_SPEC="voyage:${EMBED_MODEL}"
    ;;
  5)
    EMBED_MODEL=$(prompt_text "Ollama embedding model" "nomic-embed-text")
    EMBED_DIM=$(prompt_text "Dimensions" "768")
    EMBED_PROVIDER="ollama-docker"
    EMBED_GBRAIN_SPEC="ollama:${EMBED_MODEL}"
    EMBED_API_BASE="http://ollama:11434"
    info "Ollama will run as a Docker container alongside gbrain."
    info "First start will pull the model (may take a few minutes)."
    ;;
  6)
    EMBED_HOST_URL=$(prompt_text "Ollama host URL" "http://host.docker.internal:11434")
    EMBED_MODEL=$(prompt_text "Ollama embedding model" "nomic-embed-text")
    EMBED_DIM=$(prompt_text "Dimensions" "768")
    EMBED_PROVIDER="ollama-host"
    EMBED_GBRAIN_SPEC="ollama:${EMBED_MODEL}"
    EMBED_API_BASE="$EMBED_HOST_URL"
    info "Make sure Ollama is running on the host and the model is pulled."
    info "  ollama pull ${EMBED_MODEL}"
    ;;
  7)
    EMBED_PROVIDER="skip"
    warn "Embedding not configured. Search features won't work until configured."
    ;;
esac

if [ "$EMBED_PROVIDER" != "skip" ]; then
  ok "Embedding: ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
fi

# ══════════════════════════════════════════════════════
# Step 4: Server
# ══════════════════════════════════════════════════════
header "Step 4/4: Server"

GBRAIN_PORT=$(prompt_text "HTTP port" "3000")
ADMIN_SECRET_DEFAULT=$(gen_secret)
ADMIN_SECRET=$(prompt_text "Admin secret" "[auto-generated]")
ADMIN_SECRET="${ADMIN_SECRET:-$ADMIN_SECRET_DEFAULT}"
[ "$ADMIN_SECRET" = "[auto-generated]" ] && ADMIN_SECRET="$ADMIN_SECRET_DEFAULT"

GBRAIN_REF=$(prompt_text "gbrain version (git ref)" "master")

# ══════════════════════════════════════════════════════
# Summary & Confirm
# ══════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Configuration               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Database:${NC}    ${PG_USER}@postgres/${PG_DB}"
if [ "$LLM_PROVIDER" != "skip" ]; then
  echo -e "  ${CYAN}LLM:${NC}        ${LLM_MODEL} (${LLM_API_BASE})"
else
  echo -e "  ${CYAN}LLM:${NC}        not configured"
fi
if [ "$EMBED_PROVIDER" != "skip" ]; then
  echo -e "  ${CYAN}Embedding:${NC}   ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
else
  echo -e "  ${CYAN}Embedding:${NC}   not configured"
fi
echo -e "  ${CYAN}Port:${NC}        ${GBRAIN_PORT}"
echo -e "  ${CYAN}gbrain ref:${NC}  ${GBRAIN_REF}"
echo ""

if ! prompt_yesno "Deploy with this configuration?" "Y"; then
  echo "Aborted. No files written."
  exit 0
fi

# ══════════════════════════════════════════════════════
# Write .env
# ══════════════════════════════════════════════════════
info "Writing .env ..."

cat > .env <<EOF
# ── Generated by deploy-docker.sh — $(date -Iseconds) ──

# Database
POSTGRES_PASSWORD=${PG_PASS}
POSTGRES_USER=${PG_USER}
POSTGRES_DB=${PG_DB}

# Server
GBRAIN_PORT=${GBRAIN_PORT}
GBRAIN_ADMIN_SECRET=${ADMIN_SECRET}
GBRAIN_REF=${GBRAIN_REF}
EOF

# LLM config
if [ "$LLM_PROVIDER" != "skip" ]; then
  cat >> .env <<EOF

# LLM (enrichment / extraction)
LLM_API_BASE=${LLM_API_BASE}
LLM_API_KEY=${LLM_API_KEY}
LLM_MODEL=${LLM_MODEL}
EOF
fi

# Embedding config
if [ "$EMBED_PROVIDER" != "skip" ]; then
  cat >> .env <<EOF

# Embedding
EMBEDDING_PROVIDER=${EMBED_PROVIDER}
EMBEDDING_GBRAIN_SPEC=${EMBED_GBRAIN_SPEC}
EMBEDDING_DIM=${EMBED_DIM}
EOF

  case "$EMBED_PROVIDER" in
    openai)
      cat >> .env <<EOF
OPENAI_API_KEY=${EMBED_API_KEY}
EOF
      ;;
    custom)
      cat >> .env <<EOF
OPENAI_API_KEY=${EMBED_API_KEY}
OPENAI_BASE_URL=${EMBED_API_BASE}
EOF
      ;;
    zeroentropy)
      cat >> .env <<EOF
ZEROENTROPY_API_KEY=${EMBED_API_KEY}
EOF
      ;;
    voyage)
      cat >> .env <<EOF
VOYAGE_API_KEY=${EMBED_API_KEY}
EOF
      ;;
    ollama-docker)
      cat >> .env <<EOF
OLLAMA_ENABLED=true
OLLAMA_EMBED_MODEL=${EMBED_MODEL}
EOF
      ;;
    ollama-host)
      cat >> .env <<EOF
OLLAMA_ENABLED=false
OLLAMA_HOST=${EMBED_API_BASE}
OLLAMA_EMBED_MODEL=${EMBED_MODEL}
EOF
      ;;
  esac
fi

ok ".env written."

# ══════════════════════════════════════════════════════
# Build & Deploy
# ══════════════════════════════════════════════════════
source .env

COMPOSE_ARGS=("--env-file" ".env")
if [ "${EMBED_PROVIDER:-}" = "ollama-docker" ]; then
  COMPOSE_ARGS+=("--profile" "ollama")
fi

info "Building images..."
docker compose "${COMPOSE_ARGS[@]}" build

info "Starting services..."
docker compose "${COMPOSE_ARGS[@]}" up -d

# Pull Ollama model if using Docker Ollama
if [ "${EMBED_PROVIDER:-}" = "ollama-docker" ]; then
  info "Pulling Ollama model: ${EMBED_MODEL}..."
  docker compose exec ollama ollama pull "${EMBED_MODEL}"
fi

# Wait for gbrain
info "Waiting for gbrain to start..."
max_wait=120
elapsed=0
while [ $elapsed -lt $max_wait ]; do
  if curl -sf "http://localhost:${GBRAIN_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $max_wait ]; then
  warn "gbrain did not respond within ${max_wait}s."
  info "Check logs: docker compose logs gbrain"
  exit 1
fi

EXTERNAL_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  gbrain is live!${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  MCP endpoint:   ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp${NC}"
echo -e "  Admin dashboard: ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/admin${NC}"
echo ""
echo -e "  Next: ${BOLD}./register-agent.sh <name> <scope>${NC}"
echo ""
