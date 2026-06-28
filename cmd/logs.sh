#!/usr/bin/env bash
# cmd/logs.sh — tail service logs (docker-only)
load_config

FOLLOW=false; LINES=50; SERVICE=gbrain
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--follow) FOLLOW=true; shift ;;
    -n)          LINES="$2"; shift 2 ;;
    caddy|postgres|gbrain|ollama) SERVICE="$1"; shift ;;
    *)           shift ;;
  esac
done

ARGS=("logs" "$SERVICE" "-n" "$LINES")
[ "$FOLLOW" = true ] && ARGS+=("-f")
docker compose "${ARGS[@]}"
