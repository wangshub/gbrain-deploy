# Hermes

## MCP Connection

Hermes connects to gbrain via the HTTP MCP endpoint.

## Setup

1. Register the agent:
```bash
./register-agent.sh hermes "read write"
```

2. Configure Hermes to use the gbrain MCP server:

Set environment variables:
```bash
GBRAIN_MCP_URL=http://YOUR_SERVER:3000/mcp
GBRAIN_MCP_TOKEN=<client_secret>
```

Or add to Hermes' MCP server configuration:
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

3. Install skillpack (if Hermes supports skillpack scaffolding):
```bash
gbrain skillpack scaffold --all
```

## Scope Recommendation

Register with `read write` scope for full agent capabilities.
