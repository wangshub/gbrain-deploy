#!/usr/bin/env bash
# cmd/test.sh — smoke tests for gbrain deployment via container exec
set -uo pipefail

load_config

PASS=0
FAIL=0
RESULTS=()

pass() { PASS=$((PASS + 1)); RESULTS+=("${GREEN}  ✓${NC} $1"); }
fail() { FAIL=$((FAIL + 1)); RESULTS+=("${RED}  ✗${NC} $1 ${DIM}($2)${NC}"); }

echo ""
echo -e "${BOLD}gbrain Smoke Tests${NC}"
echo ""

EXEC=(docker compose exec -T gbrain)

# Test 1: health (in-container)
if "${EXEC[@]}" curl -sf http://localhost:3000/health 2>/dev/null | grep -q '"ok"'; then
  pass "Health endpoint returns ok"
else
  fail "Health endpoint returns ok" "no ok in /health"
fi

# Test 2: MCP rejects unauthenticated
CODE=$("${EXEC[@]}" curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0.1"}}}' 2>/dev/null || echo 000)
[ "$CODE" = "401" ] && pass "MCP rejects unauthenticated" || fail "MCP rejects unauthenticated" "HTTP ${CODE}"

# Test 3: auth create -> token
TOK=$("${EXEC[@]}" gbrain auth create smoke-test 2>/dev/null | grep -oE 'gbrain_[A-Za-z0-9]+' | head -1)
[ -n "$TOK" ] && pass "auth create issues token" || fail "auth create issues token" "no token"

# Test 4: MCP accepts the token
if [ -n "$TOK" ]; then
  RESP=$("${EXEC[@]}" curl -s -X POST http://localhost:3000/mcp \
    -H "Authorization: Bearer ${TOK}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}' 2>/dev/null || true)
  echo "$RESP" | grep -q '"result"' && pass "MCP accepts issued token" || fail "MCP accepts issued token" "got: ${RESP:-<empty>}"
else
  fail "MCP accepts issued token" "skipped: no token"
fi

# Cleanup
[ -n "$TOK" ] && "${EXEC[@]}" gbrain auth revoke smoke-test >/dev/null 2>&1 || true

# Test 5: postgres healthy
docker compose ps 2>/dev/null | grep -q "postgres.*healthy" && pass "PostgreSQL healthy" || fail "PostgreSQL healthy" "not healthy"

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
