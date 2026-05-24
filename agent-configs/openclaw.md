# OpenClaw

## Skillpack Setup

gbrain installs as a skillpack scaffold into OpenClaw's workspace.

## On the OpenClaw host

1. Install gbrain CLI in thin-client mode:

```bash
bun install -g github:garrytan/gbrain

# Point to your shared server
export GBRAIN_MCP_URL=http://YOUR_SERVER:3000/mcp
export GBRAIN_MCP_TOKEN=<client_secret from register-agent.sh>

# Verify connection
gbrain doctor
```

2. Scaffold skillpack:

```bash
gbrain skillpack scaffold --all
```

This drops 43+ skills into OpenClaw's workspace. The agent picks them up automatically.

## Environment Variables

Set these in OpenClaw's environment:

```bash
GBRAIN_MCP_URL=http://YOUR_SERVER:3000/mcp
GBRAIN_MCP_TOKEN=<client_secret>
```

## Scope Recommendation

Register with `read write` scope:
```bash
./register-agent.sh openclaw "read write"
```
