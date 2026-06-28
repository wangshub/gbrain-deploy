#!/usr/bin/env bash
# cmd/agents.sh — register/list/revoke agents via upstream `gbrain auth`
load_config

ACTION="${1:-list}"
shift 2>/dev/null || true
CREDS_DIR="credentials"

case "$ACTION" in
  list)
    header "Registered Agents (from gbrain)"
    docker compose exec -T gbrain gbrain auth list || warn "Could not reach gbrain. Is it running?"
    ;;
  add)
    NAME="${1:?Usage: gbrain.sh agents add <name>}"
    info "Creating access token for '${NAME}'..."
    OUT=$(docker compose exec -T gbrain gbrain auth create "$NAME" 2>&1) || die "auth create failed:\n${OUT}"
    TOKEN=$(printf '%s' "$OUT" | grep -oE 'gbrain_[A-Za-z0-9]+' | head -1)
    [ -n "$TOKEN" ] || die "Could not parse token from gbrain output:\n${OUT}"

    ENDPOINT=$(agent_endpoint)
    mkdir -p "$CREDS_DIR"
    cat > "${CREDS_DIR}/${NAME}.json" <<EOF
{
  "agent_name": "${NAME}",
  "token": "${TOKEN}",
  "endpoint": "${ENDPOINT}",
  "registered_at": "$(date -Iseconds)"
}
EOF
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Agent registered: ${NAME}"
    echo "══════════════════════════════════════════════════"
    echo ""
    echo "  Token:    ${TOKEN}"
    echo "  Endpoint: ${ENDPOINT}"
    echo "  Auth:     Authorization: Bearer ${TOKEN}"
    echo ""
    echo "  Saved to ${CREDS_DIR}/${NAME}.json — the token won't be shown again."
    echo ""
    ;;
  remove)
    NAME="${1:?Usage: gbrain.sh agents remove <name>}"
    info "Revoking '${NAME}' in gbrain..."
    docker compose exec -T gbrain gbrain auth revoke "$NAME" || warn "Revoke failed (token may not exist)."
    rm -f "${CREDS_DIR}/${NAME}.json"
    ok "Agent removed: ${NAME}"
    ;;
  *)
    die "Unknown agents action: $ACTION (use: list|add|remove)"
    ;;
esac
