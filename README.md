# gbrain-deploy

One-click deployment of [gbrain](https://github.com/garrytan/gbrain) as a shared knowledge brain for multiple AI agents.

```
┌──────────────────────────────────┐
│          Docker Compose          │
│  ┌───────────┐  ┌─────────────┐ │
│  │ PostgreSQL │  │    gbrain    │ │
│  │ + pgvector │  │  HTTP MCP   │ │
│  │ (internal) │  │  (port 3000)│ │
│  └───────────┘  └─────────────┘ │
└──────────────────────────────────┘
         ▲               ▲
         │               │
   ┌─────┘    ┌─────────┤──────────┐
   │          │         │          │
┌──┴───┐ ┌───┴──┐ ┌────┴───┐ ┌───┴────┐
│OpenClaw│ │Hermes│ │Claude  │ │ Cursor │
│       │ │      │ │Code    │ │        │
└──────┘ └──────┘ └────────┘ └────────┘
```

## Quick Start

```bash
git clone <this-repo> && cd gbrain-deploy
cp .env.example .env
# Edit .env: set API key for embedding provider
./deploy.sh
```

That's it. gbrain is live at `http://YOUR_SERVER:3000`.

## Architecture

| Component | Image | Purpose |
|-----------|-------|---------|
| **PostgreSQL** | `pgvector/pgvector:pg16` | Knowledge graph + vector store |
| **gbrain** | Custom (Bun) | HTTP MCP server, admin dashboard |

gbrain runs in HTTP MCP mode (`gbrain serve --http`) with:
- **OAuth 2.1** DCR client registration
- **Scope-gated access** (read / write / admin per agent)
- **Built-in rate limiting**
- **Admin dashboard** at `/admin`

## Configuration

All config lives in `.env`:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_PASSWORD` | Yes | — | Database password |
| `GBRAIN_ADMIN_SECRET` | Yes | — | Admin auth secret |
| `ZEROENTROPY_API_KEY` | One of* | — | ZeroEntropy embedding (default provider) |
| `OPENAI_API_KEY` | One of* | — | OpenAI embedding |
| `VOYAGE_API_KEY` | one of* | — | Voyage embedding |
| `POSTGRES_DB` | No | `gbrain` | Database name |
| `POSTGRES_USER` | No | `gbrain` | Database user |
| `GBRAIN_PORT` | No | `3000` | Exposed HTTP port |
| `GBRAIN_REF` | No | `latest` | gbrain git ref (tag/branch/commit) |
| `GBRAIN_EMBEDDING_MODEL` | No | auto | e.g. `zeroentropy:zembed-1` |
| `GBRAIN_EMBEDDING_DIMENSIONS` | No | auto | e.g. `1280` |

*At least one embedding API key is required.

## Registering Agents

```bash
# Register with read + write access
./register-agent.sh claude-code "read write"

# Register read-only agent
./register-agent.sh observer "read"

# Register admin agent
./register-agent.sh admin-agent "read write admin"
```

Credentials are saved to `credentials/<agent-name>.json`.

## Agent Integration

See `agent-configs/` for detailed setup guides:

| Agent | Config File | Protocol |
|-------|------------|----------|
| Claude Code | `agent-configs/claude-code.md` | HTTP MCP |
| OpenClaw | `agent-configs/openclaw.md` | Thin-client MCP |
| Hermes | `agent-configs/hermes.md` | HTTP MCP |
| Any MCP client | `agent-configs/generic-mcp.md` | HTTP MCP / SSE |

## Backup & Migration

```bash
# Backup
./backup.sh                # -> backups/YYYYMMDD-HHMMSS/
./backup.sh /mnt/nfs       # custom output dir

# Restore
./restore.sh backups/20260524-143000/

# Migrate to new server
./backup.sh                # on old server
# copy backups/ + .env to new server
./restore.sh backups/latest   # on new server
./deploy.sh
```

## Common Operations

```bash
# View logs
docker compose logs -f gbrain

# Restart
docker compose restart gbrain

# Update gbrain to latest
GBRAIN_REF=latest docker compose build gbrain
docker compose up -d gbrain

# Health check
curl http://localhost:3000/health

# Run gbrain doctor
docker compose exec gbrain gbrain doctor

# Shell into gbrain container
docker compose exec gbrain sh
```

## Troubleshooting

**gbrain fails to start**
```bash
docker compose logs gbrain
```

**Embedding model error**
```bash
docker compose exec gbrain gbrain doctor
```

**Database connection refused**
```bash
docker compose logs postgres
docker compose exec postgres pg_isready -U gbrain
```

**Port already in use**
```bash
# Change port in .env
GBRAIN_PORT=3001
docker compose up -d
```

## License

This deployment tool is MIT licensed. gbrain itself is [MIT licensed](https://github.com/garrytan/gbrain) by Garry Tan.
