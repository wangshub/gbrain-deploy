#!/usr/bin/env bash
# cmd/test.sh — smoke tests for gbrain deployment
set -uo pipefail

load_config

COOKIE_JAR="/tmp/gbrain-smoke-cookies.txt"
rm -f "$COOKIE_JAR"

PORT="${GBRAIN_PORT:-3000}"
ADMIN_SECRET="${GBRAIN_ADMIN_SECRET:-}"

BASE="http://localhost:${PORT}"
PASS=0
FAIL=0
RESULTS=()

pass() { PASS=$((PASS + 1)); RESULTS+=("${GREEN}  ✓${NC} $1"); }
fail() { FAIL=$((FAIL + 1)); RESULTS+=("${RED}  ✗${NC} $1 ${DIM}($2)${NC}"); }

echo ""
echo -e "${BOLD}gbrain Smoke Tests${NC}"
echo -e "Target: ${BASE}"
echo ""

# Test 1: Health endpoint
RESP=$(curl -s "${BASE}/health" 2>/dev/null || true)
if echo "$RESP" | grep -q '"ok"'; then
  pass "Health endpoint returns ok"
else
  fail "Health endpoint returns ok" "got: ${RESP:-<empty>}"
fi

# Test 2: Health includes version
if echo "$RESP" | grep -q '"version"'; then
  pass "Health includes version"
else
  fail "Health includes version" "missing in response"
fi

# Test 3: Admin dashboard loads
HTTP_CODE=$(curl -s -L -o /dev/null -w "%{http_code}" "${BASE}/admin/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "Admin dashboard returns 200"
else
  fail "Admin dashboard returns 200" "HTTP ${HTTP_CODE}"
fi

# Test 4: MCP rejects unauthenticated
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE}/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' \
  2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "401" ]; then
  pass "MCP rejects unauthenticated request"
else
  fail "MCP rejects unauthenticated request" "HTTP ${HTTP_CODE}"
fi

# Resolve admin token
ADMIN_TOKEN=""
if printf '%s' "${ADMIN_SECRET}" | grep -qE '^[A-Za-z0-9_-]{32,}$' 2>/dev/null; then
  ADMIN_TOKEN="${ADMIN_SECRET}"
elif [ "$DEPLOY_MODE" = "docker" ] && command -v docker >/dev/null 2>&1; then
  ADMIN_TOKEN=$(docker compose logs gbrain 2>/dev/null \
    | grep -oE '[A-Za-z0-9_-]{50,}' | tail -1 || true)
fi

[ -z "$ADMIN_TOKEN" ] && echo -e "  ${DIM}Warning: could not resolve admin token. Auth tests skipped.${NC}"

# Test 5: Admin login
if [ -n "$ADMIN_TOKEN" ]; then
  LOGIN_RESP=$(curl -s -c "$COOKIE_JAR" -X POST "${BASE}/admin/login" \
    -H "Content-Type: application/json" \
    -d "{\"token\": \"${ADMIN_TOKEN}\"}" 2>/dev/null || true)
  if echo "$LOGIN_RESP" | grep -q '"authenticated"' || echo "$LOGIN_RESP" | grep -q '"ok"'; then
    pass "Admin login accepts bootstrap token"
  else
    fail "Admin login accepts bootstrap token" "got: ${LOGIN_RESP:-<empty>}"
  fi
else
  fail "Admin login accepts bootstrap token" "skipped: no admin token"
fi

# Test 6: Create API key via admin
API_TOKEN=""
if [ -n "$ADMIN_TOKEN" ]; then
  API_KEY_RESP=$(curl -s -b "$COOKIE_JAR" -X POST "${BASE}/admin/api/api-keys" \
    -H "Content-Type: application/json" \
    -d '{"name": "smoke-test", "scope": "read write"}' 2>/dev/null || true)
  if echo "$API_KEY_RESP" | grep -q '"token"'; then
    API_TOKEN=$(echo "$API_KEY_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
    pass "Create API key via admin"
  else
    API_KEY_RESP=$(curl -s -X POST "${BASE}/admin/api/api-keys" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"name": "smoke-test", "scope": "read write"}' 2>/dev/null || true)
    if echo "$API_KEY_RESP" | grep -q '"token"'; then
      API_TOKEN=$(echo "$API_KEY_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
      pass "Create API key via admin (Bearer auth)"
    else
      fail "Create API key via admin" "got: ${API_KEY_RESP:-<empty>}"
    fi
  fi
else
  fail "Create API key via admin" "skipped: no admin token"
fi

# Test 7: MCP accepts API token
if [ -n "$API_TOKEN" ]; then
  MCP_RESP=$(curl -s -X POST "${BASE}/mcp" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"0.1"}}}' \
    2>/dev/null || true)
  if echo "$MCP_RESP" | grep -q '"result"'; then
    pass "MCP accepts API token (initialize)"
  else
    fail "MCP accepts API token (initialize)" "got: ${MCP_RESP:-<empty>}"
  fi
else
  fail "MCP accepts API token (initialize)" "skipped: no API token"
fi

# Test 8: Docker containers (Docker only)
if [ "$DEPLOY_MODE" = "docker" ] && command -v docker >/dev/null 2>&1; then
  if docker compose ps 2>/dev/null | grep -q "postgres.*healthy"; then
    pass "PostgreSQL container is healthy"
  else
    fail "PostgreSQL container is healthy" "not healthy"
  fi
  if docker compose ps 2>/dev/null | grep -q "gbrain.*Up"; then
    pass "gbrain container is running"
  else
    fail "gbrain container is running" "not running"
  fi
fi

# Cleanup
if [ -n "$API_TOKEN" ]; then
  curl -s -b "$COOKIE_JAR" -X POST "${BASE}/admin/api/api-keys/revoke" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"smoke-test\"}" >/dev/null 2>&1 || true
fi
rm -f "$COOKIE_JAR"

# Results
echo ""
for r in "${RESULTS[@]}"; do
  echo -e "$r"
done

TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${TOTAL} total"
echo ""

[ "$FAIL" -eq 0 ]
