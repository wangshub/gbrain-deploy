#!/usr/bin/env bash
# cmd/service.sh — start/stop/restart (docker-only)
ACTION="$1"
load_config
case "$ACTION" in
  start)   info "Starting gbrain..."; docker compose start gbrain; ok "Started." ;;
  stop)    info "Stopping gbrain..."; docker compose stop gbrain; ok "Stopped." ;;
  restart) info "Restarting gbrain..."; docker compose restart gbrain; ok "Restarted." ;;
  *) die "Unknown action: $ACTION (expected: start|stop|restart)" ;;
esac
