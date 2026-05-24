# Generic MCP Client

Any MCP-compatible client can connect to the shared gbrain instance.

## Connection Info

| Field | Value |
|-------|-------|
| **Protocol** | HTTP MCP (SSE) |
| **Endpoint** | `http://YOUR_SERVER:3000/mcp` |
| **Auth** | Bearer token (from `register-agent.sh`) |
| **Admin** | `http://YOUR_SERVER:3000/admin` |

## Step 1: Register

```bash
./register-agent.sh my-agent "read write"
```

## Step 2: Configure

Most MCP clients accept a JSON config:

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

For SSE-based clients:

```
SSE endpoint: http://YOUR_SERVER:3000/sse
Headers: Authorization: Bearer <client_secret>
```

## Step 3: Verify

Test with curl:

```bash
curl http://YOUR_SERVER:3000/health
```

## Scope Reference

| Scope | Capabilities |
|-------|-------------|
| `read` | Search, query, get pages, graph traversal |
| `write` | Put pages, capture, auto-link |
| `admin` | Register clients, manage brains, doctor |

## Webhook Ingestion

For non-MCP integrations:

```bash
curl -X POST http://YOUR_SERVER:3000/ingest \
  -H "Authorization: Bearer <client_secret>" \
  -H "Content-Type: text/markdown" \
  -d "# a thought to capture"
```
