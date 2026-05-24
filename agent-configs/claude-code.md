# Claude Code

## MCP Server Configuration

After registering an agent (`./register-agent.sh claude-code`), add to your project or global settings:

**Project-level** (`.claude/settings.json` in your project):
```json
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "http://YOUR_SERVER:3000/mcp",
      "headers": {
        "Authorization": "Bearer <client_secret from register-agent.sh>"
      }
    }
  }
}
```

**Global** (`~/.claude/settings.json`):
```json
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "http://YOUR_SERVER:3000/mcp",
      "headers": {
        "Authorization": "Bearer <client_secret>"
      }
    }
  }
}
```

## Thin-Client Mode

For environments where Claude Code can't run gbrain locally:

```bash
export GBRAIN_MCP_URL=http://YOUR_SERVER:3000/mcp
export GBRAIN_MCP_TOKEN=<client_secret>
```

## Available MCP Operations

After connecting, Claude Code can use all gbrain MCP operations:
- `search` — hybrid search
- `put_page` / `get_page` — read/write pages
- `graph_query` — knowledge graph traversal
- `capture` — quick capture thoughts
- `think` — grounded temporal answers
- `find_trajectory` — timeline queries
