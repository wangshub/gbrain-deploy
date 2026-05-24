#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is not available."

# ── .env ─────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  # Generate random secrets
  PG_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  ADMIN_SECRET=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  sed -i.bak \
    -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${PG_PASS}/" \
    -e "s/^GBRAIN_ADMIN_SECRET=.*/GBRAIN_ADMIN_SECRET=${ADMIN_SECRET}/" \
    .env
  rm -f .env.bak
  ok "Created .env with generated secrets."
  warn "Edit .env to add your embedding provider API key (e.g. OPENAI_API_KEY)."
else
  ok ".env already exists, skipping generation."
fi

# ── Validate required keys ──────────────────────────
source .env

[ "${POSTGRES_PASSWORD:-}" = "change-me-to-a-strong-password" ] && die "POSTGRES_PASSWORD is not set. Edit .env first."
[ "${GBRAIN_ADMIN_SECRET:-}" = "change-me-to-a-strong-secret" ] && die "GBRAIN_ADMIN_SECRET is not set. Edit .env first."

has_key=0
for key in ZEROENTROPY_API_KEY OPENAI_API_KEY VOYAGE_API_KEY; do
  if [ -n "${!key:-}" ]; then
    has_key=1
    break
  fi
done
[ "$has_key" -eq 0 ] && warn "No embedding API key set. gbrain init may fail. Set one in .env."

# ── Build & Start ────────────────────────────────────
info "Building gbrain image..."
docker compose build

info "Starting services..."
docker compose up -d

info "Waiting for gbrain to become healthy..."
max_wait=120
elapsed=0
while [ $elapsed -lt $max_wait ]; do
  if curl -sf http://localhost:${GBRAIN_PORT:-3000}/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $max_wait ]; then
  die "gbrain did not become healthy within ${max_wait}s. Check: docker compose logs gbrain"
fi

ok "gbrain is running."

# ── Print status ─────────────────────────────────────
GBRAIN_PORT=${GBRAIN_PORT:-3000}
EXTERNAL_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  gbrain is live!${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo ""
echo "  MCP endpoint:   http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp"
echo "  Admin dashboard: http://${EXTERNAL_HOST}:${GBRAIN_PORT}/admin"
echo "  Admin secret:    ${GBRAIN_ADMIN_SECRET}"
echo ""
echo "  Next steps:"
echo "    1. Register agents:  ./register-agent.sh <agent-name> <scope>"
echo "    2. See agent-configs/ for per-agent setup guides"
echo ""
