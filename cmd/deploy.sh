#!/usr/bin/env bash
# cmd/deploy.sh — interactive deployment wizard (Docker or Local)
set -euo pipefail

# ── OS Detection (local mode) ────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then echo "macos"
  elif [ -f /etc/debian_version ]; then echo "debian"
  elif [ -f /etc/redhat-release ]; then echo "rhel"
  elif [ -f /etc/arch-release ]; then echo "arch"
  else echo "unknown"
  fi
}

# ── Shared deploy steps ──────────────────────────────

step_llm() {
  header "AI Model (for enrichment, extraction, synthesis)"
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
      warn "LLM not configured. Features won't work until configured."
      ;;
  esac
  [ "$LLM_PROVIDER" != "skip" ] && ok "LLM: ${LLM_MODEL} via ${LLM_API_BASE}"
}

step_embedding() {
  header "Embedding Model (for vector search)"
  local choices=("$@")
  EMBED_CHOICE=$(prompt_select "Embedding Provider:" "${choices[@]}")
  local idx=1
  case "$1" in
    *Docker*)
      # Docker mode: 7 options
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
          warn "Embedding not configured."
          ;;
      esac
      ;;
    *)
      # Local mode: 6 options
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
          warn "Embedding not configured."
          ;;
      esac
      ;;
  esac
  [ "$EMBED_PROVIDER" != "skip" ] && ok "Embedding: ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
}

write_llm_env() {
  local file="$1"
  if [ "$LLM_PROVIDER" != "skip" ]; then
    cat >> "$file" <<EOF

# LLM (enrichment / extraction)
LLM_API_BASE=${LLM_API_BASE}
LLM_API_KEY=${LLM_API_KEY}
LLM_MODEL=${LLM_MODEL}
EOF
  fi
}

write_embed_env_docker() {
  local file="$1"
  if [ "$EMBED_PROVIDER" != "skip" ]; then
    cat >> "$file" <<EOF

# Embedding
EMBEDDING_PROVIDER=${EMBED_PROVIDER}
EMBEDDING_GBRAIN_SPEC=${EMBED_GBRAIN_SPEC}
EMBEDDING_DIM=${EMBED_DIM}
EOF
    case "$EMBED_PROVIDER" in
      openai)       echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      custom)       echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "$file"
                    echo "OPENAI_BASE_URL=${EMBED_API_BASE}" >> "$file" ;;
      zeroentropy)  echo "ZEROENTROPY_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      voyage)       echo "VOYAGE_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      ollama-docker)
                    echo "OLLAMA_ENABLED=true" >> "$file"
                    echo "OLLAMA_EMBED_MODEL=${EMBED_MODEL}" >> "$file" ;;
      ollama-host)  echo "OLLAMA_ENABLED=false" >> "$file"
                    echo "OLLAMA_HOST=${EMBED_API_BASE}" >> "$file"
                    echo "OLLAMA_EMBED_MODEL=${EMBED_MODEL}" >> "$file" ;;
    esac
  fi
}

write_embed_env_local() {
  local file="$1"
  if [ "$EMBED_PROVIDER" != "skip" ]; then
    cat >> "$file" <<EOF

# Embedding
EMBEDDING_GBRAIN_SPEC=${EMBED_GBRAIN_SPEC}
EMBEDDING_DIM=${EMBED_DIM}
EOF
    case "$EMBED_PROVIDER" in
      openai)      echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      custom)      echo "OPENAI_API_KEY=${EMBED_API_KEY}" >> "$file"
                   echo "OPENAI_BASE_URL=${EMBED_API_BASE}" >> "$file" ;;
      zeroentropy) echo "ZEROENTROPY_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      voyage)      echo "VOYAGE_API_KEY=${EMBED_API_KEY}" >> "$file" ;;
      ollama)      echo "OLLAMA_HOST=${EMBED_OLLAMA_URL}" >> "$file" ;;
    esac
  fi
}

write_git_env() {
  local file="$1"
  if [ "$GIT_PROVIDER" != "skip" ]; then
    cat >> "$file" <<EOF

# Git sync
BRAIN_GIT_REMOTE=${BRAIN_GIT_REMOTE}
BRAIN_GIT_BRANCH=${BRAIN_GIT_BRANCH}
BRAIN_GIT_TOKEN=${BRAIN_GIT_TOKEN}
BRAIN_GIT_USER=${BRAIN_GIT_USER}
BRAIN_GIT_EMAIL=${BRAIN_GIT_EMAIL}
EOF
  fi
}

step_git_sync() {
  GIT_PROVIDER="skip"
  if prompt_yesno "Sync brain data to a git repo?" "N"; then
    BRAIN_GIT_REMOTE=$(prompt_text "Git remote URL" "https://github.com/your-org/your-brain.git")
    BRAIN_GIT_BRANCH=$(prompt_text "Git branch" "main")
    if prompt_yesno "Use a personal access token for authentication?" "Y"; then
      BRAIN_GIT_TOKEN=$(prompt_password "Git token (e.g. GitHub PAT)")
    else
      BRAIN_GIT_TOKEN=""
    fi
    BRAIN_GIT_USER=$(prompt_text "Git author name" "gbrain")
    BRAIN_GIT_EMAIL=$(prompt_text "Git author email" "gbrain@localhost")
    GIT_PROVIDER="configured"
    ok "Git sync: ${BRAIN_GIT_REMOTE} (${BRAIN_GIT_BRANCH})"
  else
    warn "Git sync not configured."
  fi
}

# ══════════════════════════════════════════════════════
# Deploy: Docker
# ══════════════════════════════════════════════════════
deploy_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is not available."

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     gbrain Docker Deployment Setup       ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

  # Step 1: Database
  header "Step 1/5: Database"
  PG_PASS_DEFAULT=$(gen_secret)
  PG_PASS=$(prompt_text "PostgreSQL password" "[auto-generated]")
  PG_PASS="${PG_PASS:-$PG_PASS_DEFAULT}"
  [ "$PG_PASS" = "[auto-generated]" ] && PG_PASS="$PG_PASS_DEFAULT"
  PG_USER=$(prompt_text "PostgreSQL user" "gbrain")
  PG_DB=$(prompt_text "PostgreSQL database" "gbrain")
  ok "Database: ${PG_USER}@localhost/${PG_DB}"

  # Step 2: LLM
  header "Step 2/5: AI Model"
  step_llm

  # Step 3: Embedding
  header "Step 3/5: Embedding Model"
  step_embedding \
    "OpenAI" \
    "OpenAI-compatible (custom URL)" \
    "ZeroEntropy" \
    "Voyage AI" \
    "Ollama (local, runs in Docker)" \
    "Ollama (connect to host)" \
    "Skip — configure later"

  # Step 4: Git sync
  header "Step 4/5: Git Sync"
  step_git_sync

  # Step 5: Server
  header "Step 5/5: Server"
  GBRAIN_PORT=$(prompt_text "HTTP port" "3000")
  ADMIN_SECRET_DEFAULT=$(gen_secret)
  ADMIN_SECRET=$(prompt_text "Admin secret" "[auto-generated]")
  ADMIN_SECRET="${ADMIN_SECRET:-$ADMIN_SECRET_DEFAULT}"
  [ "$ADMIN_SECRET" = "[auto-generated]" ] && ADMIN_SECRET="$ADMIN_SECRET_DEFAULT"
  GBRAIN_REF=$(prompt_text "gbrain version (git ref)" "master")

  # Summary
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║              Configuration               ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}Database:${NC}    ${PG_USER}@postgres/${PG_DB}"
  [ "$LLM_PROVIDER" != "skip" ] && echo -e "  ${CYAN}LLM:${NC}        ${LLM_MODEL} (${LLM_API_BASE})"
  [ "$EMBED_PROVIDER" != "skip" ] && echo -e "  ${CYAN}Embedding:${NC}   ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
  echo -e "  ${CYAN}Port:${NC}        ${GBRAIN_PORT}"
  echo -e "  ${CYAN}gbrain ref:${NC}  ${GBRAIN_REF}"
  [ "$GIT_PROVIDER" != "skip" ] && echo -e "  ${CYAN}Git sync:${NC}    ${BRAIN_GIT_REMOTE} (${BRAIN_GIT_BRANCH})"
  echo ""

  if ! prompt_yesno "Deploy with this configuration?" "Y"; then
    echo "Aborted. No files written."
    exit 0
  fi

  # Write .env
  info "Writing .env ..."
  cat > .env <<EOF
# ── Generated by gbrain.sh deploy — $(date -Iseconds) ──

# Database
POSTGRES_PASSWORD=${PG_PASS}
POSTGRES_USER=${PG_USER}
POSTGRES_DB=${PG_DB}

# Server
GBRAIN_PORT=${GBRAIN_PORT}
GBRAIN_ADMIN_SECRET=${ADMIN_SECRET}
GBRAIN_REF=${GBRAIN_REF}
EOF
  write_llm_env ".env"
  write_embed_env_docker ".env"
  write_git_env ".env"
  ok ".env written."

  # Build & Deploy
  source .env
  COMPOSE_ARGS=("--env-file" ".env")
  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && COMPOSE_ARGS+=("--profile" "ollama")

  info "Building images..."
  docker compose "${COMPOSE_ARGS[@]}" build

  info "Starting services..."
  docker compose "${COMPOSE_ARGS[@]}" up -d

  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && {
    info "Pulling Ollama model: ${EMBED_MODEL}..."
    docker compose exec ollama ollama pull "${EMBED_MODEL}"
  }

  info "Waiting for gbrain to start..."
  if ! wait_for_health "${GBRAIN_PORT}" 120; then
    warn "gbrain did not respond within 120s."
    info "Check logs: gbrain.sh logs"
    exit 1
  fi

  EXTERNAL_HOST=$(get_external_host)
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}  gbrain is live!${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  MCP endpoint:   ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp${NC}"
  echo -e "  Admin dashboard: ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/admin${NC}"
  echo ""
  echo -e "  Next: ${BOLD}gbrain.sh agents add <name> <scope>${NC}"
  echo ""
}

# ══════════════════════════════════════════════════════
# Deploy: Local
# ══════════════════════════════════════════════════════
deploy_local() {
  OS=$(detect_os)
  info "Detected OS: ${OS}"

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     gbrain Local Deployment Setup        ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

  # Step 0: Prerequisites
  header "Step 0/6: Prerequisites"
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

  if command -v psql >/dev/null 2>&1; then
    PG_VERSION=$(psql --version | grep -oE '[0-9]+' | head -1)
    ok "PostgreSQL ${PG_VERSION} already installed."
  else
    warn "PostgreSQL not found."
    if prompt_yesno "Install PostgreSQL + pgvector now?" "Y"; then
      info "Installing PostgreSQL + pgvector..."
      case "$OS" in
        debian) sudo apt update && sudo apt install -y postgresql postgresql-server-dev-all pgvector ;;
        rhel)   sudo yum install -y postgresql-server pgvector
                sudo postgresql-setup initdb 2>/dev/null || true
                sudo systemctl enable postgresql && sudo systemctl start postgresql ;;
        macos)  brew install postgresql pgvector && brew services start postgresql ;;
        arch)   sudo pacman -S postgresql pgvector ;;
        *)      die "Unsupported OS. Install PostgreSQL + pgvector manually." ;;
      esac
      ok "PostgreSQL installed."
    else
      die "PostgreSQL is required. Install manually."
    fi
  fi

  info "Checking pgvector extension..."
  if psql -U postgres -c "SELECT 'vector'::regtype" >/dev/null 2>&1; then
    ok "pgvector extension available."
  else
    warn "pgvector extension not found."
    if prompt_yesno "Try to install pgvector?" "Y"; then
      case "$OS" in
        debian) sudo apt install -y "postgresql-$(psql --version | grep -oE '[0-9]+' | head -1)-pgvector" ;;
        rhel)   sudo yum install -y "pgvector_$(psql --version | grep -oE '[0-9]+' | head -1)" ;;
        macos)  brew install pgvector ;;
        arch)   sudo pacman -S pgvector ;;
      esac
    fi
  fi

  # Step 1: Database
  header "Step 1/6: Database"
  PG_USER=$(prompt_text "PostgreSQL user" "gbrain")
  PG_DB=$(prompt_text "PostgreSQL database" "gbrain")
  PG_HOST=$(prompt_text "PostgreSQL host" "localhost")
  PG_PORT=$(prompt_text "PostgreSQL port" "5432")

  if prompt_yesno "Use password authentication?" "Y"; then
    PG_PASS=$(prompt_password "PostgreSQL password for user '${PG_USER}'")
    DB_URL="postgres://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}"
  else
    PG_PASS=""
    DB_URL="postgres://${PG_HOST}:${PG_PORT}/${PG_DB}"
  fi
  ok "Database URL: ${DB_URL}"

  # Step 2: LLM
  header "Step 2/6: AI Model"
  step_llm

  # Step 3: Embedding
  header "Step 3/6: Embedding Model"
  step_embedding \
    "OpenAI" \
    "OpenAI-compatible (custom URL)" \
    "ZeroEntropy" \
    "Voyage AI" \
    "Ollama (localhost)" \
    "Skip — configure later"

  # Step 4: Server
  header "Step 4/6: Server"
  GBRAIN_PORT=$(prompt_text "HTTP port" "3000")
  ADMIN_SECRET_DEFAULT=$(gen_secret)
  ADMIN_SECRET=$(prompt_text "Admin secret" "[auto-generated]")
  ADMIN_SECRET="${ADMIN_SECRET:-$ADMIN_SECRET_DEFAULT}"
  [ "$ADMIN_SECRET" = "[auto-generated]" ] && ADMIN_SECRET="$ADMIN_SECRET_DEFAULT"
  GBRAIN_REF=$(prompt_text "gbrain version (git ref)" "master")

  # Step 5: Service
  header "Step 5/6: Service"
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

  # Summary
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║              Configuration               ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}Mode:${NC}        native (bare-metal)"
  echo -e "  ${CYAN}Database:${NC}    ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB}"
  [ "$LLM_PROVIDER" != "skip" ] && echo -e "  ${CYAN}LLM:${NC}        ${LLM_MODEL} (${LLM_API_BASE})"
  [ "$EMBED_PROVIDER" != "skip" ] && echo -e "  ${CYAN}Embedding:${NC}   ${EMBED_GBRAIN_SPEC} (${EMBED_DIM}d)"
  echo -e "  ${CYAN}Port:${NC}        ${GBRAIN_PORT}"
  echo -e "  ${CYAN}Service:${NC}     ${SERVICE_TYPE}"
  echo ""

  if ! prompt_yesno "Install with this configuration?" "Y"; then
    echo "Aborted."
    exit 0
  fi

  # Install gbrain
  info "Installing gbrain..."
  bun install -g "github:garrytan/gbrain#${GBRAIN_REF}"
  ok "gbrain installed."

  # Setup Database
  info "Setting up PostgreSQL database..."
  PGCONN_ARGS=()
  [ -n "$PG_HOST" ] && PGCONN_ARGS+=("-h" "$PG_HOST")
  [ -n "$PG_PORT" ] && PGCONN_ARGS+=("-p" "$PG_PORT")

  if [ -n "$PG_PASS" ]; then
    psql "${PGCONN_ARGS[@]}" -U postgres -v pg_user="$PG_USER" -v pg_pass="$PG_PASS" -c \
      "CREATE USER :pg_user WITH PASSWORD :'pg_pass';" 2>/dev/null || true
    psql "${PGCONN_ARGS[@]}" -U postgres -v pg_user="$PG_USER" -v pg_pass="$PG_PASS" -c \
      "ALTER USER :pg_user WITH PASSWORD :'pg_pass';" 2>/dev/null || true
  fi
  psql "${PGCONN_ARGS[@]}" -U postgres -v pg_user="$PG_USER" -v pg_db="$PG_DB" -c \
    "CREATE DATABASE :pg_db OWNER :pg_user;" 2>/dev/null || true
  psql "${PGCONN_ARGS[@]}" -U postgres -d "${PG_DB}" -c \
    "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
  ok "Database ready."

  # Write env file
  ENV_DIR="$HOME/.gbrain-deploy"
  mkdir -p "$ENV_DIR"
  cat > "${ENV_DIR}/.env.local" <<EOF
# ── Generated by gbrain.sh deploy — $(date -Iseconds) ──

# Database
DATABASE_URL=${DB_URL}

# Server
GBRAIN_PORT=${GBRAIN_PORT}
GBRAIN_ADMIN_SECRET=${ADMIN_SECRET}
EOF
  write_llm_env "${ENV_DIR}/.env.local"
  write_embed_env_local "${ENV_DIR}/.env.local"
  ok "Config written to ${ENV_DIR}/.env.local"

  # Write start script
  GBRAIN_BIN=$(command -v gbrain)
  cat > "${ENV_DIR}/start.sh" <<START_EOF
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="\$HOME/.gbrain-deploy/.env.local"
[ -f "\$ENV_FILE" ] || { echo "Config not found: \$ENV_FILE"; exit 1; }
set -a; source "\$ENV_FILE"; set +a
exec ${GBRAIN_BIN} serve --http --port "\${GBRAIN_PORT:-3000}" --bind 0.0.0.0
START_EOF
  chmod +x "${ENV_DIR}/start.sh"
  ok "Start script: ${ENV_DIR}/start.sh"

  # Initialize gbrain
  info "Initializing gbrain..."
  set -a; source "${ENV_DIR}/.env.local"; set +a
  if [ -n "${LLM_API_BASE:-}" ] && [ -z "${OPENAI_BASE_URL:-}" ]; then
    export OPENAI_BASE_URL="${LLM_API_BASE}"
  fi
  if [ -n "${LLM_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
    export OPENAI_API_KEY="${LLM_API_KEY}"
  fi

  INIT_ARGS=""
  [ -n "${EMBEDDING_GBRAIN_SPEC:-}" ] && INIT_ARGS="$INIT_ARGS --embedding-model ${EMBEDDING_GBRAIN_SPEC}"
  [ -n "${EMBEDDING_DIM:-}" ] && INIT_ARGS="$INIT_ARGS --embedding-dimensions ${EMBEDDING_DIM}"
  if [ -z "${EMBEDDING_GBRAIN_SPEC:-}" ] && [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${ZEROENTROPY_API_KEY:-}" ] && [ -z "${VOYAGE_API_KEY:-}" ]; then
    INIT_ARGS="$INIT_ARGS --no-embedding"
  fi
  # shellcheck disable=SC2086
  gbrain init $INIT_ARGS
  ok "gbrain initialized."

  info "Installing gbrain skills..."
  gbrain install || warn "gbrain install failed, some skills may be missing."
  ok "Skills installed."

  # Step 6: Git sync
  header "Step 6/6: Git Sync"
  GBRAIN_DIR="$HOME/.gbrain"
  if [ ! -d "$GBRAIN_DIR/.git" ]; then
    git init "$GBRAIN_DIR"
    ok "Brain directory initialized as git repo."
  fi
  if [ -z "$(git -C "$GBRAIN_DIR" config user.name 2>/dev/null)" ]; then
    git -C "$GBRAIN_DIR" config user.name "gbrain"
    git -C "$GBRAIN_DIR" config user.email "gbrain@localhost"
  fi

  if prompt_yesno "Sync brain data to a remote git repo?" "N"; then
    BRAIN_GIT_REMOTE=$(prompt_text "Git remote URL" "https://github.com/your-org/your-brain.git")
    BRAIN_GIT_BRANCH=$(prompt_text "Git branch" "main")
    if git -C "$GBRAIN_DIR" remote get-url origin >/dev/null 2>&1; then
      git -C "$GBRAIN_DIR" remote set-url origin "$BRAIN_GIT_REMOTE"
    else
      git -C "$GBRAIN_DIR" remote add origin "$BRAIN_GIT_REMOTE"
    fi
    echo "" >> "${ENV_DIR}/.env.local"
    echo "# Git sync" >> "${ENV_DIR}/.env.local"
    echo "BRAIN_GIT_REMOTE=${BRAIN_GIT_REMOTE}" >> "${ENV_DIR}/.env.local"
    echo "BRAIN_GIT_BRANCH=${BRAIN_GIT_BRANCH}" >> "${ENV_DIR}/.env.local"
    ok "Git remote configured: ${BRAIN_GIT_REMOTE}"
  else
    ok "Git sync skipped."
  fi

  # Setup Service
  if [ "$SERVICE_TYPE" = "systemd" ]; then
    info "Creating systemd service..."
    GBRAIN_BIN=$(command -v gbrain)
    cat > /tmp/gbrain.service <<EOF
[Unit]
Description=gbrain HTTP MCP Server
After=network.target postgresql.service

[Service]
Type=simple
User=${USER}
EnvironmentFile=${ENV_DIR}/.env.local
ExecStart=${GBRAIN_BIN} serve --http --port ${GBRAIN_PORT} --bind 0.0.0.0
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

  # Verify
  info "Waiting for gbrain..."
  if ! wait_for_health "${GBRAIN_PORT}" 30; then
    warn "gbrain did not respond within 30s."
  fi

  EXTERNAL_HOST=$(get_external_host)
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}  gbrain is live! (native install)${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  MCP endpoint:   ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp${NC}"
  echo -e "  Admin dashboard: ${CYAN}http://${EXTERNAL_HOST}:${GBRAIN_PORT}/admin${NC}"
  echo -e "  Config file:    ${CYAN}${ENV_DIR}/.env.local${NC}"
  echo ""
  echo -e "  Manage:"
  [ "$SERVICE_TYPE" = "systemd" ] && echo -e "    ${DIM}gbrain.sh restart | stop | logs${NC}"
  [ "$SERVICE_TYPE" = "launchd" ] && echo -e "    ${DIM}gbrain.sh restart | stop | logs${NC}"
  [ "$SERVICE_TYPE" = "manual" ] && echo -e "    ${DIM}${ENV_DIR}/start.sh${NC}"
  echo ""
  echo -e "  Next: ${BOLD}gbrain.sh agents add <name> <scope>${NC}"
  echo ""
}

# ══════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════
header "gbrain Deployment"
echo -e "  ${BOLD}1)${NC} Docker — Containerized, recommended"
echo -e "  ${BOLD}2)${NC} Local  — Native install, minimal overhead"
echo ""

DEPLOY_CHOICE=$(prompt_select "Select mode:" "Docker (recommended)" "Local (bare metal)")

case "$DEPLOY_CHOICE" in
  1) deploy_docker ;;
  2) deploy_local ;;
  *) die "Invalid choice" ;;
esac
