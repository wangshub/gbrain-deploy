#!/usr/bin/env bash
# cmd/deploy.sh — interactive deployment wizard (Docker)
set -euo pipefail

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
  header "Step 1/6: Database"
  PG_PASS_DEFAULT=$(gen_secret)
  PG_PASS=$(prompt_text "PostgreSQL password" "[auto-generated]")
  PG_PASS="${PG_PASS:-$PG_PASS_DEFAULT}"
  [ "$PG_PASS" = "[auto-generated]" ] && PG_PASS="$PG_PASS_DEFAULT"
  PG_USER=$(prompt_text "PostgreSQL user" "gbrain")
  PG_DB=$(prompt_text "PostgreSQL database" "gbrain")
  ok "Database: ${PG_USER}@localhost/${PG_DB}"

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
    "Ollama (local, runs in Docker)" \
    "Ollama (connect to host)" \
    "Skip — configure later"

  # Step 4: Git sync
  header "Step 4/6: Git Sync"
  step_git_sync

  # Step 5: Server
  header "Step 5/6: Server"
  GBRAIN_PORT=$(prompt_text "HTTP port" "3000")
  ADMIN_SECRET_DEFAULT=$(gen_secret)
  ADMIN_SECRET=$(prompt_text "Admin secret" "[auto-generated]")
  ADMIN_SECRET="${ADMIN_SECRET:-$ADMIN_SECRET_DEFAULT}"
  [ "$ADMIN_SECRET" = "[auto-generated]" ] && ADMIN_SECRET="$ADMIN_SECRET_DEFAULT"
  GBRAIN_REF=$(prompt_text "gbrain version (git ref)" "master")

  # Step 6/6: Network exposure
  header "Step 6/6: Network Exposure"
  EXPOSE_CHOICE=$(prompt_select "How will gbrain be reached?" \
    "Private network (Tailscale/LAN, HTTP over encrypted network)" \
    "Public domain (Caddy + automatic HTTPS)")
  case "$EXPOSE_CHOICE" in
    1)
      EXPOSE_MODE="private"
      DOMAIN=""
      ACME_EMAIL=""
      local ts_ip=""
      ts_ip=$(tailscale ip -4 2>/dev/null | head -1 || true)
      GBRAIN_BIND_ADDR=$(prompt_text "Bind gbrain port to host address" "${ts_ip:-127.0.0.1}")
      ;;
    2)
      EXPOSE_MODE="public"
      GBRAIN_BIND_ADDR="127.0.0.1"
      DOMAIN=$(prompt_text "Domain (must resolve to this server)" "brain.example.com")
      ACME_EMAIL=$(prompt_text "Email for Let's Encrypt" "you@example.com")
      ;;
  esac

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
  echo -e "  ${CYAN}Exposure:${NC}    ${EXPOSE_MODE}"
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

  BACKUP_PASSPHRASE_DEFAULT=$(gen_secret)
  cat >> .env <<EOF

# Network exposure
EXPOSE_MODE=${EXPOSE_MODE}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
GBRAIN_BIND_ADDR=${GBRAIN_BIND_ADDR}

# Backup
BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE_DEFAULT}
BACKUP_KEEP=7
EOF
  ok ".env written."

  # Build & Deploy
  source .env
  COMPOSE_ARGS=("--env-file" ".env")
  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && COMPOSE_ARGS+=("--profile" "ollama")
  [ "${EXPOSE_MODE}" = "public" ] && COMPOSE_ARGS+=("--profile" "caddy")

  info "Building images..."
  docker compose "${COMPOSE_ARGS[@]}" build
  info "Starting services..."
  docker compose "${COMPOSE_ARGS[@]}" up -d

  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && {
    info "Pulling Ollama model: ${EMBED_MODEL}..."
    docker compose exec ollama ollama pull "${EMBED_MODEL}"
  }

  info "Waiting for gbrain to start..."
  if ! wait_for_health 120; then
    warn "gbrain did not respond within 120s. Check: gbrain.sh logs"
    exit 1
  fi

  echo ""
  echo -e "${GREEN}  gbrain is live!${NC}"
  echo ""
  echo -e "  MCP endpoint:    ${CYAN}$(agent_endpoint)${NC}"
  if [ "${EXPOSE_MODE}" = "public" ]; then
    echo -e "  Admin dashboard: ${CYAN}https://${DOMAIN}/admin${NC}"
  else
    echo -e "  Admin dashboard: ${CYAN}http://${GBRAIN_BIND_ADDR}:${GBRAIN_PORT}/admin${NC}"
    echo -e "  ${DIM}For HTTPS + MagicDNS over Tailscale, run on the host:${NC}"
    echo -e "  ${DIM}  tailscale serve --bg https / http://localhost:${GBRAIN_PORT}${NC}"
  fi
  echo ""
  echo -e "  Next: ${BOLD}gbrain.sh agents add <name>${NC}"
  echo ""
}

# ══════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════
deploy_docker
