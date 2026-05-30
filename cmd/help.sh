#!/usr/bin/env bash
# cmd/help.sh — show help text

show_help() {
  local topic="${1:-}"

  if [ -n "$topic" ]; then
    case "$topic" in
      deploy)
        echo -e "${BOLD}gbrain.sh deploy${NC}"
        echo "  Run interactive deployment wizard."
        echo "  Choose Docker or local, configure DB, LLM, embedding, git sync."
        echo ""
        echo -e "  ${DIM}Equivalent to: ./deploy-docker.sh or ./deploy-local.sh${NC}"
        ;;
      status)
        echo -e "${BOLD}gbrain.sh status${NC}"
        echo "  Show service health, database status, port, agent count."
        ;;
      logs)
        echo -e "${BOLD}gbrain.sh logs [options]${NC}"
        echo "  Tail gbrain service logs."
        echo ""
        echo -e "  ${DIM}Options:${NC}"
        echo "    -f, --follow    Follow log output"
        echo "    -n N            Show last N lines (default: 50)"
        echo "    --since TIME    Show logs since time (e.g. 1h, 30m)"
        ;;
      agents)
        echo -e "${BOLD}gbrain.sh agents <subcommand>${NC}"
        echo ""
        echo -e "  ${DIM}Subcommands:${NC}"
        echo "    list                List all registered agents"
        echo "    add <name> [scope]  Register a new agent"
        echo "    remove <name>       Remove an agent's credentials"
        ;;
      backup)
        echo -e "${BOLD}gbrain.sh backup [directory]${NC}"
        echo "  Backup PostgreSQL database + brain data + config."
        echo "  Default directory: backups/"
        ;;
      restore)
        echo -e "${BOLD}gbrain.sh restore <backup-directory>${NC}"
        echo "  Restore from a previous backup."
        ;;
      config)
        echo -e "${BOLD}gbrain.sh config [get|set] [key] [value]${NC}"
        echo ""
        echo -e "  ${DIM}Usage:${NC}"
        echo "    config              Show all config"
        echo "    config get <key>    Show one config value"
        echo "    config set <k> <v>  Set a config value"
        ;;
      start|stop|restart)
        echo -e "${BOLD}gbrain.sh ${topic}${NC}"
        echo "  ${topic^} the gbrain service."
        echo "  Auto-detects Docker / systemd / launchd."
        ;;
      test)
        echo -e "${BOLD}gbrain.sh test${NC}"
        echo "  Run smoke tests against the running deployment."
        ;;
      *)
        echo -e "${RED}Unknown topic: ${topic}${NC}"
        echo "Run 'gbrain.sh help' to see all commands."
        ;;
    esac
    return
  fi

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       gbrain Deployment Manager          ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Usage:${NC} gbrain.sh <command> [options]"
  echo ""
  echo -e "  ${BOLD}Deploy & Manage:${NC}"
  echo -e "    ${CYAN}deploy${NC}     Interactive deployment wizard (Docker or local)"
  echo -e "    ${CYAN}status${NC}     Show service health and info"
  echo -e "    ${CYAN}logs${NC}       Tail service logs (-f, -n N)"
  echo -e "    ${CYAN}start${NC}      Start the gbrain service"
  echo -e "    ${CYAN}stop${NC}       Stop the gbrain service"
  echo -e "    ${CYAN}restart${NC}    Restart the gbrain service"
  echo ""
  echo -e "  ${BOLD}Data & Config:${NC}"
  echo -e "    ${CYAN}agents${NC}     Manage registered agents (list/add/remove)"
  echo -e "    ${CYAN}backup${NC}     Backup database and brain data"
  echo -e "    ${CYAN}restore${NC}    Restore from backup"
  echo -e "    ${CYAN}config${NC}     View or edit configuration"
  echo ""
  echo -e "  ${BOLD}Other:${NC}"
  echo -e "    ${CYAN}test${NC}       Run smoke tests"
  echo -e "    ${CYAN}help${NC}       Show this help (or: help <command>)"
  echo ""
  echo -e "  ${DIM}All commands: gbrain.sh help <command>${NC}"
  echo ""
}

show_help "$@"
