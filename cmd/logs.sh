#!/usr/bin/env bash
# cmd/logs.sh — tail service logs

load_config

FOLLOW=false
LINES=50
SINCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--follow) FOLLOW=true; shift ;;
    -n)          LINES="$2"; shift 2 ;;
    --since)     SINCE="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

SVC_TYPE=$(detect_service_type)

if [ "$SVC_TYPE" = "docker" ]; then
  DOCKER_ARGS=("logs" "gbrain" "-n" "$LINES")
  [ "$FOLLOW" = true ] && DOCKER_ARGS+=("-f")
  docker compose "${DOCKER_ARGS[@]}"
elif [ "$SVC_TYPE" = "systemd" ]; then
  JOURNAL_ARGS=("-u" "gbrain" "-n" "$LINES")
  [ "$FOLLOW" = true ] && JOURNAL_ARGS+=("-f")
  [ -n "$SINCE" ] && JOURNAL_ARGS+=("--since" "$SINCE")
  journalctl "${JOURNAL_ARGS[@]}"
elif [ "$SVC_TYPE" = "launchd" ]; then
  LOG_FILE="$HOME/Library/Logs/gbrain.log"
  if [ ! -f "$LOG_FILE" ]; then
    warn "Log file not found: $LOG_FILE"
    info "Checking stderr log..."
    LOG_FILE="$HOME/Library/Logs/gbrain.err"
  fi
  if [ -f "$LOG_FILE" ]; then
    if [ "$FOLLOW" = true ]; then
      tail -f -n "$LINES" "$LOG_FILE"
    else
      tail -n "$LINES" "$LOG_FILE"
    fi
  else
    die "No log files found."
  fi
else
  die "Manual mode: check your terminal output."
fi
