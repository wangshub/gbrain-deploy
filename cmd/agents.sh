#!/usr/bin/env bash
# cmd/agents.sh — list/add/remove agents

load_config

AGENT_ACTION="${1:-list}"
shift 2>/dev/null || true

case "$AGENT_ACTION" in
  list)
    CREDS_DIR="credentials"
    if [ ! -d "$CREDS_DIR" ] || [ -z "$(ls -A "$CREDS_DIR"/*.json 2>/dev/null)" ]; then
      warn "No agents registered."
      info "Add one: gbrain.sh agents add <name> [scope]"
      exit 0
    fi

    header "Registered Agents"
    for f in "$CREDS_DIR"/*.json; do
      NAME=$(grep -o '"agent_name":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      SCOPE=$(grep -o '"scope":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      DATE=$(grep -o '"registered_at":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      printf "  ${CYAN}%-20s${NC} scope=${DIM}%s${NC}  registered=%s\n" "$NAME" "$SCOPE" "$DATE"
    done
    echo ""
    ;;
  add)
    AGENT_NAME="${1:?Usage: gbrain.sh agents add <name> [scope]}"
    SCOPE="${2:-read write}"

    GBRAIN_PORT=${GBRAIN_PORT:-3000}
    ADMIN_SECRET=${GBRAIN_ADMIN_SECRET:?GBRAIN_ADMIN_SECRET not set}

    echo "Registering agent '${AGENT_NAME}' with scope '${SCOPE}'..."

    RESPONSE=$(curl -sf -X POST "http://localhost:${GBRAIN_PORT}/register" \
      -H "Authorization: Bearer ${ADMIN_SECRET}" \
      -H "Content-Type: application/json" \
      -d "$(printf '{"client_name":"%s","scope":"%s"}' \
        "$(echo "$AGENT_NAME" | sed 's/"/\\"/g')" \
        "$(echo "$SCOPE" | sed 's/"/\\"/g')")" \
      2>&1) || {
        echo "Registration failed. gbrain may not support DCR yet."
        echo "Falling back to admin-secret token mode."
        echo ""
        EXTERNAL_HOST=$(get_external_host)
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

    CLIENT_ID=$(echo "$RESPONSE" | grep -o '"client_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    CLIENT_SECRET=$(echo "$RESPONSE" | grep -o '"client_secret":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
      echo "Unexpected response from server:"
      echo "$RESPONSE"
      exit 1
    fi

    EXTERNAL_HOST=$(get_external_host)

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
    ;;
  remove)
    AGENT_NAME="${1:?Usage: gbrain.sh agents remove <name>}"
    CREDS_FILE="credentials/${AGENT_NAME}.json"
    if [ ! -f "$CREDS_FILE" ]; then
      die "Agent not found: $AGENT_NAME"
    fi
    rm "$CREDS_FILE"
    ok "Agent removed: $AGENT_NAME"
    ;;
  *)
    die "Unknown agents action: $AGENT_ACTION (use: list|add|remove)"
    ;;
esac
