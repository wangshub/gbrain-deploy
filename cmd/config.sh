#!/usr/bin/env bash
# cmd/config.sh — view or edit configuration

load_config

CONFIG_ACTION="${1:-view}"
shift 2>/dev/null || true

case "$CONFIG_ACTION" in
  view|"")
    header "Current Configuration"
    if is_docker_mode; then
      echo -e "  ${BOLD}Mode:${NC}    Docker"
      echo -e "  ${BOLD}Config:${NC}  .env"
      echo ""
      grep -v "^#" .env | grep -v "^$" | while IFS='=' read -r key val; do
        # Mask sensitive values
        case "$key" in
          *API_KEY|*PASSWORD|*SECRET|*TOKEN)
            val="${val:0:4}****"
            ;;
        esac
        printf "  ${CYAN}%-25s${NC} %s\n" "$key" "$val"
      done
    else
      echo -e "  ${BOLD}Mode:${NC}    Local"
      echo -e "  ${BOLD}Config:${NC}  $HOME/.gbrain-deploy/.env.local"
      echo ""
      grep -v "^#" "$HOME/.gbrain-deploy/.env.local" | grep -v "^$" | while IFS='=' read -r key val; do
        case "$key" in
          *API_KEY|*PASSWORD|*SECRET|*TOKEN)
            val="${val:0:4}****"
            ;;
        esac
        printf "  ${CYAN}%-25s${NC} %s\n" "$key" "$val"
      done
    fi
    echo ""
    ;;
  get)
    CONFIG_KEY="${1:?Usage: gbrain.sh config get <key>}"
    if is_docker_mode; then
      grep "^${CONFIG_KEY}=" .env | cut -d= -f2-
    else
      grep "^${CONFIG_KEY}=" "$HOME/.gbrain-deploy/.env.local" | cut -d= -f2-
    fi
    ;;
  set)
    CONFIG_KEY="${1:?Usage: gbrain.sh config set <key> <value>}"
    CONFIG_VAL="${2:?Usage: gbrain.sh config set <key> <value>}"
    if is_docker_mode; then
      CONFIG_FILE=".env"
    else
      CONFIG_FILE="$HOME/.gbrain-deploy/.env.local"
    fi

    if grep -q "^${CONFIG_KEY}=" "$CONFIG_FILE"; then
      # Update existing
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^${CONFIG_KEY}=.*|${CONFIG_KEY}=${CONFIG_VAL}|" "$CONFIG_FILE"
      else
        sed -i "s|^${CONFIG_KEY}=.*|${CONFIG_KEY}=${CONFIG_VAL}|" "$CONFIG_FILE"
      fi
      ok "Updated: ${CONFIG_KEY}"
    else
      # Add new
      echo "${CONFIG_KEY}=${CONFIG_VAL}" >> "$CONFIG_FILE"
      ok "Added: ${CONFIG_KEY}"
    fi

    info "Restart service to apply: gbrain.sh restart"
    ;;
  *)
    die "Unknown config action: $CONFIG_ACTION (use: view|get|set)"
    ;;
esac
