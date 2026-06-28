#!/usr/bin/env bash
# cmd/config.sh — view or edit configuration

load_config

CONFIG_ACTION="${1:-view}"
shift 2>/dev/null || true

case "$CONFIG_ACTION" in
  view|"")
    header "Current Configuration (.env)"
    grep -v '^#' .env | grep -v '^$' | while IFS='=' read -r key val; do
      case "$key" in
        *API_KEY|*PASSWORD|*SECRET|*TOKEN|*PASSPHRASE) val="${val:0:4}****" ;;
      esac
      printf "  ${CYAN}%-25s${NC} %s\n" "$key" "$val"
    done
    echo ""
    ;;
  get)
    CONFIG_KEY="${1:?Usage: gbrain.sh config get <key>}"
    grep "^${CONFIG_KEY}=" .env | cut -d= -f2-
    ;;
  set)
    CONFIG_KEY="${1:?Usage: gbrain.sh config set <key> <value>}"
    CONFIG_VAL="${2:?Usage: gbrain.sh config set <key> <value>}"
    CONFIG_FILE=".env"

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
