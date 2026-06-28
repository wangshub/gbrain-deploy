#!/usr/bin/env bash
# cmd/status.sh — service status (docker-only)
load_config
header "gbrain Status"

if docker compose ps gbrain 2>/dev/null | grep -q "Up"; then
  echo -e "  ${BOLD}Service:${NC}   ${GREEN}●${NC} running"
else
  echo -e "  ${BOLD}Service:${NC}   ${RED}●${NC} stopped"
fi

echo -e "  ${BOLD}Exposure:${NC}  ${EXPOSE_MODE:-private}"
echo -e "  ${BOLD}Port:${NC}      ${GBRAIN_PORT:-3000}"

if docker compose exec -T gbrain curl -sf http://localhost:3000/health >/dev/null 2>&1; then
  echo -e "  ${BOLD}Health:${NC}    ${GREEN}●${NC} healthy"
else
  echo -e "  ${BOLD}Health:${NC}    ${YELLOW}●${NC} unreachable"
fi

if [ "${EXPOSE_MODE:-private}" = "public" ]; then
  echo -e "  ${BOLD}Caddy:${NC}     $(docker compose --profile caddy ps caddy 2>/dev/null | grep -q Up && echo "${GREEN}● up${NC}" || echo "${RED}● down${NC}")"
fi

if [ -d credentials ]; then
  N=$(find credentials -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${BOLD}Agents:${NC}    ${N} local credential file(s)"
fi
echo -e "  ${BOLD}Endpoint:${NC}  $(agent_endpoint)"
echo ""
