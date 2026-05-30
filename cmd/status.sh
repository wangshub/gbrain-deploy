#!/usr/bin/env bash
# cmd/status.sh — show service status

load_config

header "gbrain Status"

SVC_TYPE=$(detect_service_type)
PORT="${GBRAIN_PORT:-3000}"
HOST=$(get_external_host)

# Service status
echo -e "  ${BOLD}Mode:${NC}      ${DEPLOY_MODE}"

if [ "$SVC_TYPE" = "docker" ]; then
  if docker compose ps gbrain 2>/dev/null | grep -q "Up"; then
    echo -e "  ${BOLD}Service:${NC}   ${GREEN}●${NC} running (Docker)"
  else
    echo -e "  ${BOLD}Service:${NC}   ${RED}●${NC} stopped (Docker)"
  fi
elif [ "$SVC_TYPE" = "systemd" ]; then
  if systemctl is-active --quiet gbrain 2>/dev/null; then
    UPTIME=$(systemctl show gbrain --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    echo -e "  ${BOLD}Service:${NC}   ${GREEN}●${NC} running (systemd, since ${UPTIME})"
  else
    echo -e "  ${BOLD}Service:${NC}   ${RED}●${NC} stopped (systemd)"
  fi
elif [ "$SVC_TYPE" = "launchd" ]; then
  if launchctl list | grep -q com.gbrain.server 2>/dev/null; then
    echo -e "  ${BOLD}Service:${NC}   ${GREEN}●${NC} running (launchd)"
  else
    echo -e "  ${BOLD}Service:${NC}   ${RED}●${NC} stopped (launchd)"
  fi
else
  echo -e "  ${BOLD}Service:${NC}   ${YELLOW}●${NC} manual mode"
fi

echo -e "  ${BOLD}Port:${NC}      ${PORT}"

# Database status
if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
  echo -e "  ${BOLD}Database:${NC}  ${GREEN}●${NC} healthy"
else
  echo -e "  ${BOLD}Database:${NC}  ${YELLOW}●${NC} unreachable (service may be down)"
fi

# Agent count
CREDS_DIR="credentials"
if [ -d "$CREDS_DIR" ]; then
  AGENT_COUNT=$(find "$CREDS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${BOLD}Agents:${NC}    ${AGENT_COUNT} registered"
fi

# Endpoint
echo -e "  ${BOLD}Endpoint:${NC}  http://${HOST}:${PORT}/mcp"
echo ""
