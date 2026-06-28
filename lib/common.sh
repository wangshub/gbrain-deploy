#!/usr/bin/env bash
# lib/common.sh — shared functions for gbrain-deploy
# Source this file from any script: source "$(dirname "$0")/lib/common.sh"

# ── Colors ───────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── Output helpers ───────────────────────────────────
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

# ── Utilities ────────────────────────────────────────
gen_secret() { openssl rand -base64 24 | tr -d '/+=' | head -c 32; }

get_external_host() {
  hostname -I 2>/dev/null | awk '{print $1}' || hostname 2>/dev/null || echo "YOUR_SERVER_IP"
}

# ── Config loading (docker-only) ─────────────────────
load_config() {
  [ -f .env ] || die "No .env found. Run './gbrain.sh deploy' first."
  set -a; source .env; set +a
  DEPLOY_MODE="docker"
}

# ── Health check (via container) ─────────────────────
wait_for_health() {
  local max_wait="${1:-60}" elapsed=0
  while [ "$elapsed" -lt "$max_wait" ]; do
    if docker compose exec -T gbrain curl -sf http://localhost:3000/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

# ── Endpoint + compose helpers ───────────────────────
agent_endpoint() {
  if [ "${EXPOSE_MODE:-private}" = "public" ]; then
    echo "https://${DOMAIN}/mcp"
  else
    echo "http://${GBRAIN_BIND_ADDR:-127.0.0.1}:${GBRAIN_PORT:-3000}/mcp"
  fi
}

compose_profile_args() {
  [ "${EXPOSE_MODE:-private}" = "public" ] && echo "--profile caddy"
}
