#!/usr/bin/env bash
# cmd/service.sh — start/stop/restart

ACTION="$1"

load_config

SVC_TYPE=$(detect_service_type)

case "$ACTION" in
  start)
    info "Starting gbrain service..."
    if [ "$SVC_TYPE" = "docker" ]; then
      docker compose start gbrain
    elif [ "$SVC_TYPE" = "systemd" ]; then
      sudo systemctl start gbrain
    elif [ "$SVC_TYPE" = "launchd" ]; then
      launchctl load ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true
    else
      die "Manual mode: run $HOME/.gbrain-deploy/start.sh"
    fi
    ok "gbrain started."
    ;;
  stop)
    info "Stopping gbrain service..."
    if [ "$SVC_TYPE" = "docker" ]; then
      docker compose stop gbrain
    elif [ "$SVC_TYPE" = "systemd" ]; then
      sudo systemctl stop gbrain
    elif [ "$SVC_TYPE" = "launchd" ]; then
      launchctl unload ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true
    else
      warn "Manual mode: stop the process manually."
    fi
    ok "gbrain stopped."
    ;;
  restart)
    info "Restarting gbrain service..."
    if [ "$SVC_TYPE" = "docker" ]; then
      docker compose restart gbrain
    elif [ "$SVC_TYPE" = "systemd" ]; then
      sudo systemctl restart gbrain
    elif [ "$SVC_TYPE" = "launchd" ]; then
      launchctl unload ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true
      sleep 1
      launchctl load ~/Library/LaunchAgents/com.gbrain.server.plist 2>/dev/null || true
    else
      die "Manual mode: restart manually."
    fi
    ok "gbrain restarted."
    ;;
  *)
    die "Unknown action: $ACTION (expected: start|stop|restart)"
    ;;
esac
