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
  echo "${choice:-1}"
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

# ── OS Detection ─────────────────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then echo "macos"
  elif [ -f /etc/debian_version ]; then echo "debian"
  elif [ -f /etc/redhat-release ]; then echo "rhel"
  elif [ -f /etc/arch-release ]; then echo "arch"
  else echo "unknown"
  fi
}

OS=$(detect_os)
info "Detected OS: ${OS}"

# ══════════════════════════════════════════════════════
# Step 0: Prerequisites
# ══════════════════════════════════════════════════════
header "Step 0/5: Prerequisites"

# ── bun ──────────────────────────────────────────────
if command -v bun >/dev/null 2>&1; then
  ok "bun $(bun --version) already installed."
else
  warn "bun not found."
  if prompt_yesno "Install bun now?" "Y"; then
    info "Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
    ok "bun installed."
  else
    die "bun is required. Install manually: https://bun.sh"
  fi
fi

# ── PostgreSQL ───────────────────────────────────────
if command -v psql >/dev/null 2>&1; then
  PG_VERSION=$(psql --version | grep -oE '[0-9]+' | head -1)
  ok "PostgreSQL ${PG_VERSION} already installed."
else
  warn "PostgreSQL not found."
  if prompt_yesno "Install PostgreSQL + pgvector now?" "Y"; then
    info "Installing PostgreSQL + pgvector..."
    case "$OS" in
      debian)
        sudo apt update
        sudo apt install -y postgresql postgresql-server-dev-all pgvector
        ;;
      rhel)
        sudo yum install -y postgresql-server pgvector
        sudo postgresql-setup initdb 2>/dev/null || true
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        ;;
      macos)
        brew install postgresql pgvector
        brew services start postgresql
        ;;
      arch)
        sudo pacman -S postgresql pgvector
        ;;
      *)
        die "Unsupported OS. Install PostgreSQL + pgvector manually."
        ;;
    esac
    ok "PostgreSQL installed."
  else
    die "PostgreSQL is required. Install manually."
  fi
fi

# ── pgvector extension ───────────────────────────────
info "Checking pgvector extension..."
if psql -U postgres -c "SELECT 'vector'::regtype" >/dev/null 2>&1; then
  ok "pgvector extension available."
else
  warn "pgvector extension not found in PostgreSQL."
  if prompt_yesno "Try to install pgvector?" "Y"; then
    case "$OS" in
      debian)  sudo apt install -y postgresql-$(psql --version | grep -oE '[0-9]+' | head -1)-pgvector ;;
      rhel)    sudo yum install -y pgvector_$(psql --version | grep -oE '[0-9]+' | head -1) ;;
      macos)   brew install pgvector ;;
      arch)    sudo pacman -S pgvector ;;
    esac
  fi
fi

# ══════════════════════════════════════════════════════
# Step 1: Database
# ══════════════════════════════════════════════════════
header "Step 1/5: Database"

PG_USER=$(prompt_text "PostgreSQL user" "gbrain")
PG_DB=$(prompt_text "PostgreSQL database" "gbrain")
PG_HOST=$(prompt_text "PostgreSQL host" "localhost")
PG_PORT=$(prompt_text "PostgreSQL port" "5432")

# Ask for password or use peer auth
if prompt_yesno "Use password authentication?" "Y"; then
  PG_PASS=$(prompt_password "PostgreSQL password for user '${PG_USER}'")
  DB_URL="postgres://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}"
else
  PG_PASS=""
  DB_URL="postgres://${PG_HOST}:${PG_PORT}/${PG_DB}"
fi

ok "Database URL: ${DB_URL}"

# ══════════════════════════════════════════════════════
# Step 2: AI Model (LLM)
# ══════════════════════════════════════════════════════
header "Step 2/5: AI Model (for enrichment, extraction, synthesis)"

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
    warn "LLM not configured. Configure later by editing .env.local"
    ;;
esac

[ "$LLM_PROVIDER" != "skip" ] && ok "LLM: ${LLM_MODEL} via ${LLM_API_BASE}"

# ══════════════════════════════════════════════════════
# Step 3: Embedding Model
# ══════════════════════════════════════════════════════
header "Step 3/5: Embedding Model (for vector search)"

EMBED_CHOICE=$(prompt_select "Embedding Provider:" \
  "OpenAI" \
  "OpenAI-compatible (custom URL)" \
  "ZeroEntropy" \
  "Voyage AI" \
  "Ollama (localhost)" \
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
    EMBED_OLLAMA_URL=$(prompt_text "Ollama URL" "http://localhost:11434")
    EMBED_MODEL=$(prompt_text "Ollama embedding model" "nomic-embed-text")
    EMBED_DIM=$(prompt_text "Dimensions" "768")
    EMBED_PROVIDER="ollama"
    EMBED_GBRAIN_SPEC="ollama:${EMBED_MODEL}"
    info "Make sure Ollama is running: ollama serve"
    info "Pull the model first: ollama pull ${EMBED_MODEL}"
    ;;
  6)
    EMBED_PROVIDER="skip"
    warn "Embedding not configured. Configure later by editing .env.local"
    ;;
esac

[ "$EMBED_PROVIDER" != "skip" ] && ok "Embedding: ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"

# ══════════════════════════════════════════════════════
# Step 4: Server
# ══════════════════════════════════════════════════════
header "Step 4/5: Server"

GBRAIN_PORT=$(prompt_text "HTTP port" "3000")
ADMIN_SECRET_DEFAULT=$(gen_secret)
ADMIN_SECRET=$(prompt_text "Admin secret" "[auto-generated]")
ADMIN_SECRET="${ADMIN_SECRET:-$ADMIN_SECRET_DEFAULT}"
[ "$ADMIN_SECRET" = "[auto-generated]" ] && ADMIN_SECRET="$ADMIN_SECRET_DEFAULT"

GBRAIN_REF=$(prompt_text "gbrain version (git ref)" "latest")

# ══════════════════════════════════════════════════════
# Step 5: Service
# ══════════════════════════════════════════════════════
header "Step 5/5: Service"

if [ "$OS" = "macos" ]; then
  SERVICE_TYPE="launchd"
  info "macOS detected — will create a launchd plist."
else
  SERVICE_CHOICE=$(prompt_select "Service management:" \
    "systemd (Linux standard)" \
    "No service — start manually" \
  )
  case "$SERVICE_CHOICE" in
    1) SERVICE_TYPE="systemd" ;;
    2) SERVICE_TYPE="manual" ;;
  esac
fi

# ══════════════════════════════════════════════════════
# Summary & Confirm
# ══════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Configuration               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Mode:${NC}        native (bare-metal)"
echo -e "  ${CYAN}Database:${NC}    ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB}"
[ "$LLM_PROVIDER" != "skip" ] && \
  echo -e "  ${CYAN}LLM:${NC}        ${LLM_MODEL} (${LLM_API_BASE})"
[ "$EMBED_PROVIDER" != "skip" ] && \
  echo -e "  ${CYAN}Embedding:${NC}   ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
echo -e "  ${CYAN}Port:${NC}        ${GBRAIN_PORT}"
echo -e "  ${CYAN}Service:${NC}     ${SERVICE_TYPE}"
echo ""

if ! prompt_yesno "Install with this configuration?" "Y"; then
  echo "Aborted."
  exit 0
fi

# ══════════════════════════════════════════════════════
# Install
# ══════════════════════════════════════════════════════

# ── Install gbrain ──────────────────────────────────
info "Installing gbrain..."
bun install -g "github:garrytan/gbrain#${GBRAIN_REF}"
ok "gbrain installed."

# ── Setup Database ──────────────────────────────────
info "Setting up PostgreSQL database..."

# Create user if not exists
PGCONN_ARGS=()
[ -n "$PG_HOST" ] && PGCONN_ARGS+=("-h" "$PG_HOST")
[ -n "$PG_PORT" ] && PGCONN_ARGS+=("-p" "$PG_PORT")

# Try to create user (ignore error if exists)
if [ -n "$PG_PASS" ]; then
  psql "${PGCONN_ARGS[@]}" -U postgres -c \
    "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" 2>/dev/null || true
  psql "${PGCONN_ARGS[@]}" -U postgres -c \
    "ALTER USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" 2>/dev/null || true
fi

# Create database
psql "${PGCONN_ARGS[@]}" -U postgres -c \
  "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};" 2>/dev/null || true

# Enable pgvector
psql "${PGCONN_ARGS[@]}" -U postgres -d "${PG_DB}" -c \
  "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true

ok "Database ready."

# ── Write env file ──────────────────────────────────
ENV_DIR="$HOME/.gbrain-deploy"
mkdir -p "$ENV_DIR"

cat > "${ENV_DIR}/.env.local" <<EOF
# ── Generated by deploy-local.sh — $(date -Iseconds) ──

# Database
DATABASE_URL=${DB_URL}

# Server
GBRAIN_PORT=${GBRAIN_PORT}
GBRAIN_ADMIN_SECRET=${ADMIN_SECRET}
EOF

if [ "$LLM_PROVIDER" != "skip" ]; then
  cat >> "${ENV_DIR}/.env.local" <<EOF

# LLM
LLM_API_BASE=${LLM_API_BASE}
LLM_API_KEY=${LLM_API_KEY}
LLM_MODEL=${LLM_MODEL}
EOF
fi

if [ "$EMBED_PROVIDER" != "skip" ]; then
  cat >> "${ENV_DIR}/.env.local" <<EOF

# Embedding
EMBEDDING_GBRAIN_SPEC=${EMBED_GBRAIN_SPEC}
EMBEDDING_DIM=${EMBED_DIM}
EOF

  case "$EMBED_PROVIDER" in
    openai)   echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "${ENV_DIR}/.env.local" ;;
    custom)
      echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "${ENV_DIR}/.env.local"
      echo "OPENAI_BASE_URL=${EMBED_API_BASE}" >> "${ENV_DIR}/.env.local"
      ;;
    zeroentropy) echo "ZEROENTROPY_API_KEY=${EMBED_API_KEY}" >> "${ENV_DIR}/.env.local" ;;
    voyage)      echo "VOYAGE_API_KEY=${EMBED_API_KEY}" >> "${ENV_DIR}/.env.local" ;;
    ollama)      echo "OLLAMA_HOST=${EMBED_OLLAMA_URL}" >> "${ENV_DIR}/.env.local" ;;
  esac
fi

ok "Config written to ${ENV_DIR}/.env.local"

# ── Write start script ──────────────────────────────
cat > "${ENV_DIR}/start.sh" <<'START_EOF'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$HOME/.gbrain-deploy/.env.local"
[ -f "$ENV_FILE" ] || { echo "Config not found: $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a
exec gbrain serve --http --port "${GBRAIN_PORT:-3000}"
START_EOF
chmod +x "${ENV_DIR}/start.sh"
ok "Start script: ${ENV_DIR}/start.sh"

# ── Initialize gbrain ───────────────────────────────
info "Initializing gbrain..."
set -a; source "${ENV_DIR}/.env.local"; set +a

# Map LLM config to gbrain env
if [ -n "${LLM_API_BASE:-}" ]; then
  export OPENAI_BASE_URL="${LLM_API_BASE}"
fi
if [ -n "${LLM_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  export OPENAI_API_KEY="${LLM_API_KEY}"
fi

INIT_ARGS=""
[ -n "${EMBEDDING_GBRAIN_SPEC:-}" ] && INIT_ARGS="$INIT_ARGS --embedding-model ${EMBEDDING_GBRAIN_SPEC}"
[ -n "${EMBEDDING_DIM:-}" ] && INIT_ARGS="$INIT_ARGS --embedding-dimensions ${EMBEDDING_DIM}"

# shellcheck disable=SC2086
gbrain init $INIT_ARGS
ok "gbrain initialized."

# ── Setup Service ───────────────────────────────────
if [ "$SERVICE_TYPE" = "systemd" ]; then
  info "Creating systemd service..."
  BUN_BIN=$(command -v bun)
  GBRAIN_BIN=$(command -v gbrain)
  cat > /tmp/gbrain.service <<EOF
[Unit]
Description=gbrain HTTP MCP Server
After=network.target postgresql.service

[Service]
Type=simple
User=${USER}
EnvironmentFile=${ENV_DIR}/.env.local
ExecStart=${GBRAIN_BIN} serve --http --port ${GBRAIN_PORT}
Restart=on-failure
RestartSec=5
WorkingDirectory=${HOME}

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /tmp/gbrain.service /etc/systemd/system/gbrain.service
  sudo systemctl daemon-reload
  sudo systemctl enable gbrain
  sudo systemctl start gbrain
  ok "systemd service installed and started."

elif [ "$SERVICE_TYPE" = "launchd" ]; then
  info "Creating launchd plist..."
  START_SCRIPT="${ENV_DIR}/start.sh"
  cat > "${HOME}/Library/LaunchAgents/com.gbrain.server.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.gbrain.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${START_SCRIPT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${PATH}</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/gbrain.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/gbrain.err</string>
</dict>
</plist>
EOF

  launchctl load "${HOME}/Library/LaunchAgents/com.gbrain.server.plist" 2>/dev/null || true
  ok "launchd service installed and started."
fi

# ── Verify ──────────────────────────────────────────
info "Waiting for gbrain..."
max_wait=30
elapsed=0
while [ $elapsed -lt $max_wait ]; do
  if curl -sf "http://localhost:${GBRAIN_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

EXTERNAL_HOST=$(hostname 2>/dev/null || echo "YOUR_SERVER_IP")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  gbrain is live! (native install)${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  MCP endpoint:   ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp${NC}"
echo -e "  Admin dashboard: ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/admin${NC}"
echo -e "  Config file:    ${CYAN}${ENV_DIR}/.env.local${NC}"
echo ""
echo -e "  Manage service:"
if [ "$SERVICE_TYPE" = "systemd" ]; then
  echo -e "    ${DIM}sudo systemctl status|restart|stop gbrain${NC}"
elif [ "$SERVICE_TYPE" = "launchd" ]; then
  echo -e "    ${DIM}launchctl unload ~/Library/LaunchAgents/com.gbrain.server.plist${NC}"
  echo -e "    ${DIM}launchctl load ~/Library/LaunchAgents/com.gbrain.server.plist${NC}"
else
  echo -e "    ${DIM}${ENV_DIR}/start.sh${NC}"
fi
echo ""
echo -e "  Next: ${BOLD}./register-agent.sh <name> <scope>${NC}"
echo ""
