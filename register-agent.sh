#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# ── Args ─────────────────────────────────────────────
AGENT_NAME="${1:?Usage: register-agent.sh <agent-name> [scope]}"
SCOPE="${2:-read write}"

# ── Load config — support both Docker and local deploy ──
LOCAL_ENV="$HOME/.gbrain-deploy/.env.local"
if [ -f .env ]; then
  source .env
  DEPLOY_MODE="docker"
elif [ -f "$LOCAL_ENV" ]; then
  set -a; source "$LOCAL_ENV"; set +a
  DEPLOY_MODE="local"
else
  echo "No config found. Run ./deploy-docker.sh or ./deploy-local.sh first." >&2
  exit 1
fi

GBRAIN_PORT=${GBRAIN_PORT:-3000}
ADMIN_SECRET=${GBRAIN_ADMIN_SECRET:?GBRAIN_ADMIN_SECRET not set}

# ── Register via DCR ─────────────────────────────────
echo "Registering agent '${AGENT_NAME}' with scope '${SCOPE}'..."

RESPONSE=$(curl -sf -X POST "http://localhost:${GBRAIN_PORT}/register" \
  -H "Authorization: Bearer ${ADMIN_SECRET}" \
  -H "Content-Type: application/json" \
  -d "{\"client_name\": \"${AGENT_NAME}\", \"scope\": \"${SCOPE}\"}" \
  2>&1) || {
    echo "Registration failed. gbrain may not support DCR yet."
    echo "Falling back to admin-secret token mode."
    echo ""
    EXTERNAL_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)
    echo "Agent: ${AGENT_NAME}"
    echo "Token: ${ADMIN_SECRET}"
    echo "Endpoint: http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp"
    echo "Scope: ${SCOPE}"
    echo ""
    echo "Add to your agent's MCP config:"
    echo "  URL: http://<server>:${GBRAIN_PORT}/mcp"
    echo "  Auth: Bearer ${ADMIN_SECRET}"
    exit 0
  }

# ── Parse response ───────────────────────────────────
CLIENT_ID=$(echo "$RESPONSE" | grep -o '"client_id":"[^"]*"' | head -1 | cut -d'"' -f4)
CLIENT_SECRET=$(echo "$RESPONSE" | grep -o '"client_secret":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "Unexpected response from server:"
  echo "$RESPONSE"
  exit 1
fi

EXTERNAL_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)

echo ""
echo "══════════════════════════════════════════════════"
echo "  Agent registered: ${AGENT_NAME}"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Client ID:     ${CLIENT_ID}"
echo "  Client Secret: ${CLIENT_SECRET}"
echo "  Endpoint:      http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp"
echo "  Scope:         ${SCOPE}"
echo ""
echo "  Save these credentials — the secret won't be shown again."
echo ""

# ── Save to local file ──────────────────────────────
CREDS_DIR="credentials"
mkdir -p "$CREDS_DIR"
cat > "${CREDS_DIR}/${AGENT_NAME}.json" <<EOF
{
  "agent_name": "${AGENT_NAME}",
  "client_id": "${CLIENT_ID}",
  "client_secret": "${CLIENT_SECRET}",
  "endpoint": "http://${EXTERNAL_HOST}:${GBRAIN_PORT}/mcp",
  "scope": "${SCOPE}",
  "deploy_mode": "${DEPLOY_MODE}",
  "registered_at": "$(date -Iseconds)"
}
EOF
echo "  Credentials saved to ${CREDS_DIR}/${AGENT_NAME}.json"
