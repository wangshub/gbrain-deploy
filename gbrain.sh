#!/usr/bin/env bash
# gbrain.sh — unified CLI for gbrain deployment management
set -euo pipefail

cd "$(dirname "$0")"

# Source shared library
source lib/common.sh

# Parse command
CMD="${1:-help}"
shift 2>/dev/null || true

# Route to command handler
case "$CMD" in
  deploy)
    source cmd/deploy.sh
    ;;
  status)
    source cmd/status.sh
    ;;
  logs)
    source cmd/logs.sh "$@"
    ;;
  agents)
    source cmd/agents.sh "$@"
    ;;
  backup)
    source cmd/backup.sh "$@"
    ;;
  restore)
    source cmd/restore.sh "$@"
    ;;
  config)
    source cmd/config.sh "$@"
    ;;
  start|stop|restart)
    source cmd/service.sh "$CMD"
    ;;
  test)
    source cmd/test.sh
    ;;
  help|--help|-h)
    source cmd/help.sh "$@"
    ;;
  *)
    die "Unknown command: $CMD\n  Run 'gbrain.sh help' for usage."
    ;;
esac
