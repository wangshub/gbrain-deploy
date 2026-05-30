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

# ── Config loading ───────────────────────────────────
# Auto-detect deploy mode and load config.
# Sets: DEPLOY_MODE (docker|local), GBRAIN_PORT, GBRAIN_ADMIN_SECRET, etc.
load_config() {
  local local_env="$HOME/.gbrain-deploy/.env.local"
  if [ -f .env ]; then
    set -a; source .env; set +a
    DEPLOY_MODE="docker"
  elif [ -f "$local_env" ]; then
    set -a; source "$local_env"; set +a
    DEPLOY_MODE="local"
  else
    die "No config found. Run './gbrain.sh deploy' or './deploy-docker.sh' first."
  fi
}

# ── Health check ─────────────────────────────────────
wait_for_health() {
  local port="${1:-${GBRAIN_PORT:-3000}}"
  local max_wait="${2:-30}"
  local elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    if curl -sf "http://localhost:${port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# ── Deploy mode detection ────────────────────────────
# Returns 0 if docker mode, 1 if local mode
is_docker_mode() {
  [ -f .env ]
}

is_local_mode() {
  [ ! -f .env ]
}

# ── Service helpers ──────────────────────────────────
detect_service_type() {
  if is_docker_mode; then
    echo "docker"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "launchd"
  elif systemctl list-unit-files gbrain.service >/dev/null 2>&1; then
    echo "systemd"
  else
    echo "manual"
  fi
}
