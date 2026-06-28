# Docker-only 重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 gbrain-deploy 重构为仅 Docker、双暴露模式（公网 Caddy HTTPS / 私网 HTTP）、加密轮转备份、并用上游真实 `gbrain auth` 机制签发 agent token 的简洁部署工具。

**Architecture:** 删除 Local/裸机全部代码路径，统一走 docker compose。网络暴露由 `.env` 的 `EXPOSE_MODE` 决定：`public` 启用 Caddy profile 做 Let's Encrypt 反代、gbrain 不对外发布端口；`private` 不起 Caddy、gbrain 端口绑定到 `GBRAIN_BIND_ADDR`（默认 127.0.0.1，Tailscale 场景填 tailnet IP），靠 WireGuard/内网加密。

**Tech Stack:** Bash、docker compose v2、pgvector/pgvector:pg16、oven/bun（gbrain 容器）、caddy:2、openssl（备份加密，已有依赖）。

## Global Constraints

- 所有脚本 `set -euo pipefail`（test.sh 用 `set -uo pipefail`，保持原样）。
- 校验命令：`for f in gbrain.sh lib/*.sh cmd/*.sh scripts/entrypoint.sh; do bash -n "$f"; done` 必须全过。
- 颜色/输出/prompt 助手沿用 `lib/common.sh`，风格不变。
- 敏感值掩码：key 含 `API_KEY|PASSWORD|SECRET|TOKEN|PASSPHRASE` 在 `config view` 中显示为前 4 位 + `****`。
- `.env` 是 Docker 模式唯一配置源；`.gitignore` 已含 `.env`/`credentials/`/`backups/`，不改。
- agent token 由 `docker compose exec -T gbrain gbrain auth create <name>` 签发，格式 `gbrain_<hex>`；**禁止**再把 `GBRAIN_ADMIN_SECRET` 当 agent token。
- 备份加密用 `openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:"$BACKUP_PASSPHRASE"`。备份保留份数 `BACKUP_KEEP`，默认 7。
- 新增 `.env` 键：`EXPOSE_MODE`(public|private)、`DOMAIN`、`ACME_EMAIL`、`GBRAIN_BIND_ADDR`(默认127.0.0.1)、`BACKUP_PASSPHRASE`、`BACKUP_KEEP`(默认7)。保留键：`POSTGRES_PASSWORD/USER/DB`、`GBRAIN_PORT`、`GBRAIN_ADMIN_SECRET`、`GBRAIN_REF`、`LLM_*`、embedding 相关、`BRAIN_GIT_*`。

> **偏离 spec 说明（已采纳）：** spec 写"age 优先、openssl 回退"。实现改为 **openssl 单一路径**。理由：age 的口令模式 `age -p` 只能交互读 TTY，无法用 `.env` 的 `BACKUP_PASSPHRASE` 非交互脚本化；openssl 本就是已有依赖、原生支持 `-pass pass:`，更简洁且契合"口令来自 .env"。

---

## File Structure

| 文件 | 动作 | 职责 |
|---|---|---|
| `docker-compose.yml` | 改 | 三/四服务：postgres、gbrain（端口绑 `GBRAIN_BIND_ADDR`）、caddy（profile）、ollama（profile）；加 gbrain healthcheck |
| `Caddyfile` | 建 | 公网模式反代模板 `{$DOMAIN}` → `gbrain:3000` |
| `Dockerfile` | 改 | 加 `curl`；不吞 `bun run build` 错误 |
| `scripts/entrypoint.sh` | 改 | git token 改用 credential-store（不入 remote URL） |
| `.env.example` | 改 | 新增暴露/备份键，去掉 Local 相关注释 |
| `lib/common.sh` | 改 | docker-only：`load_config`、`wait_for_health`(exec)、新增 `agent_endpoint`/`compose_profile_args`；删 `is_local_mode`/`detect_service_type`/`is_docker_mode` |
| `cmd/deploy.sh` | 重写 | 单一 Docker 路径 + 暴露方式步骤；删 `deploy_local`/`detect_os` |
| `cmd/agents.sh` | 重写 | `gbrain auth create/list/revoke` |
| `cmd/backup.sh` | 重写 | 加密打包 + 轮转，docker-only |
| `cmd/restore.sh` | 重写 | 解密恢复，docker-only |
| `cmd/service.sh` | 改 | 仅 docker compose start/stop/restart |
| `cmd/logs.sh` | 改 | 仅 docker（gbrain，可选 caddy） |
| `cmd/status.sh` | 改 | docker-only + 暴露模式/端点显示 |
| `cmd/config.sh` | 改 | docker-only（删 local 分支） |
| `cmd/test.sh` | 改 | 经 exec 的健康检查 + auth create→MCP→revoke 流程 |
| `cmd/help.sh` | 改 | 删 local/deploy-docker.sh 旧文案 |
| `README.md` / `CLAUDE.md` / `AGENT.md` | 改 | 与 docker-only/双暴露模式一致 |

---

## Task 1: 基础设施 — compose / Caddyfile / .env.example / Dockerfile / entrypoint

**Files:**
- Modify: `docker-compose.yml`
- Create: `Caddyfile`
- Modify: `Dockerfile`
- Modify: `scripts/entrypoint.sh`
- Modify: `.env.example`

**Interfaces:**
- Produces: compose 服务 `postgres`/`gbrain`/`caddy`(profile `caddy`)/`ollama`(profile `ollama`)；gbrain 端口映射 `${GBRAIN_BIND_ADDR:-127.0.0.1}:${GBRAIN_PORT:-3000}:3000`；gbrain 有 healthcheck（`curl -sf localhost:3000/health`）。`.env` 键集见 Global Constraints。

- [ ] **Step 1: 改 `docker-compose.yml` 的 gbrain 服务端口与健康检查**

把 `gbrain` 服务的 `ports` 改为绑定地址形式，并加 healthcheck：

```yaml
  gbrain:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        GBRAIN_REF: ${GBRAIN_REF:-master}
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "${GBRAIN_BIND_ADDR:-127.0.0.1}:${GBRAIN_PORT:-3000}:3000"
    environment:
      # ... 保持现有 environment 块不变 ...
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - brain-data:/root/.gbrain
    networks:
      - gbrain-net
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:3000/health"]
      interval: 10s
      timeout: 3s
      retries: 12
```

- [ ] **Step 2: 在 compose 加 `caddy` 服务（profile 门控）**

在 `ollama` 服务之后、`gbrain` 之前或之后加入：

```yaml
  caddy:
    image: caddy:2
    profiles:
      - caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAIN: ${DOMAIN:-}
      ACME_EMAIL: ${ACME_EMAIL:-}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - gbrain
    networks:
      - gbrain-net
```

并在 `volumes:` 段加上 `caddy_data:` 与 `caddy_config:`。

- [ ] **Step 3: 创建 `Caddyfile`**

```
{
	email {$ACME_EMAIL}
}

{$DOMAIN} {
	reverse_proxy gbrain:3000
}
```

- [ ] **Step 4: 改 `Dockerfile`**

在 apt 安装行加入 `curl`（healthcheck 需要），并去掉 `bun run build` 的错误吞咽：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates postgresql-client curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${GBRAIN_REF}" https://github.com/garrytan/gbrain.git /opt/gbrain-src \
    && cd /opt/gbrain-src && bun install \
    && bun install -g file:/opt/gbrain-src \
    && mkdir -p /root/admin && cp -r /opt/gbrain-src/admin/dist /root/admin/
```

（说明：删掉原 `bun run build 2>/dev/null; true` 这一步——上游 `bin` 直接指向 `src/cli.ts`，全局安装无需预编译；保留它只会吞错误。若后续发现确需 build，再单独加回并让其失败可见。）

- [ ] **Step 5: 改 `scripts/entrypoint.sh` 的 git token 处理**

把"sed 拼 token 进 URL"替换为 credential-store。将原 git sync 段（约 73-94 行）中构造 `REMOTE_URL` 的逻辑改为：

```sh
# Configure remote if specified
if [ -n "${BRAIN_GIT_REMOTE:-}" ]; then
  BRANCH="${BRAIN_GIT_BRANCH:-main}"

  # Store token via git credential-store (chmod 600), never embed in remote URL
  if [ -n "${BRAIN_GIT_TOKEN:-}" ]; then
    GIT_HOST=$(echo "$BRAIN_GIT_REMOTE" | sed -n 's|https://\([^/]*\)/.*|\1|p')
    if [ -n "$GIT_HOST" ]; then
      git -C "$BRAIN_DIR" config credential.helper store
      printf 'https://%s:x-oauth-basic@%s\n' "${BRAIN_GIT_TOKEN}" "${GIT_HOST}" > /root/.git-credentials
      chmod 600 /root/.git-credentials
    fi
  fi

  if git -C "$BRAIN_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$BRAIN_DIR" remote set-url origin "$BRAIN_GIT_REMOTE"
  else
    git -C "$BRAIN_DIR" remote add origin "$BRAIN_GIT_REMOTE"
  fi

  echo "[entrypoint] Pulling brain from remote (${BRANCH})..."
  git -C "$BRAIN_DIR" fetch origin "${BRANCH}" 2>/dev/null || true
  git -C "$BRAIN_DIR" reset --hard "origin/${BRANCH}" 2>/dev/null || true
fi
```

- [ ] **Step 6: 改 `.env.example`**

替换 Server 段并新增暴露/备份键（保留 LLM/Embedding/Git 注释段不动）：

```bash
# ── Database ─────────────────────────────────────────
POSTGRES_PASSWORD=
POSTGRES_USER=gbrain
POSTGRES_DB=gbrain

# ── Server ───────────────────────────────────────────
GBRAIN_PORT=3000
GBRAIN_ADMIN_SECRET=
GBRAIN_REF=master

# ── Network exposure ─────────────────────────────────
# public  = Caddy reverse proxy + auto HTTPS (needs DOMAIN + ACME_EMAIL)
# private = plain HTTP bound to GBRAIN_BIND_ADDR (Tailscale/LAN, WireGuard-encrypted)
EXPOSE_MODE=private
DOMAIN=
ACME_EMAIL=
# Host address gbrain's port binds to in private mode (127.0.0.1, or your tailnet 100.x IP)
GBRAIN_BIND_ADDR=127.0.0.1

# ── Backup ───────────────────────────────────────────
# Passphrase used to encrypt backups (openssl AES-256). Keep it safe — required to restore.
BACKUP_PASSPHRASE=
# How many most-recent encrypted backups to keep
BACKUP_KEEP=7
```

- [ ] **Step 7: 校验**

Run: `bash -n scripts/entrypoint.sh && echo OK`
Expected: `OK`

Run: `docker compose --env-file .env.example config -q 2>&1 | head` （若本机有 docker；无则跳过，仅人工核对 YAML 缩进）
Expected: 无报错（或仅因 `.env.example` 缺值的告警，不影响结构）。

- [ ] **Step 8: Commit**

```bash
git add docker-compose.yml Caddyfile Dockerfile scripts/entrypoint.sh .env.example
git commit -m "feat: docker-only infra — caddy profile, bound ports, git credential-store"
```

---

## Task 2: `lib/common.sh` — docker-only 助手

**Files:**
- Modify: `lib/common.sh`

**Interfaces:**
- Produces:
  - `load_config()` — 仅读 `.env`，`set -a; source .env; set +a`；无 `.env` 则 `die`。设 `DEPLOY_MODE=docker`。
  - `wait_for_health(max_wait=60)` — 经 `docker compose exec -T gbrain curl -sf http://localhost:3000/health` 探测。
  - `agent_endpoint()` — 按 `EXPOSE_MODE` 输出 MCP 端点字符串。
  - `compose_profile_args()` — `EXPOSE_MODE=public` 时输出 `--profile caddy`，否则空。
- 删除：`is_docker_mode`、`is_local_mode`、`detect_service_type`。保留：颜色、`info/ok/warn/die/header`、prompt 助手、`gen_secret`、`get_external_host`。

- [ ] **Step 1: 替换 `load_config`**

```bash
# ── Config loading (docker-only) ─────────────────────
load_config() {
  [ -f .env ] || die "No .env found. Run './gbrain.sh deploy' first."
  set -a; source .env; set +a
  DEPLOY_MODE="docker"
}
```

- [ ] **Step 2: 替换 `wait_for_health`**

```bash
# ── Health check (via container) ─────────────────────
wait_for_health() {
  local max_wait="${1:-60}" elapsed=0
  while [ "$elapsed" -lt "$max_wait" ]; do
    if docker compose exec -T gbrain curl -sf http://localhost:3000/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}
```

- [ ] **Step 3: 新增 `agent_endpoint` 与 `compose_profile_args`**

```bash
# ── Endpoint + compose helpers ───────────────────────
agent_endpoint() {
  if [ "${EXPOSE_MODE:-private}" = "public" ]; then
    echo "https://${DOMAIN}/mcp"
  else
    echo "http://${GBRAIN_BIND_ADDR:-127.0.0.1}:${GBRAIN_PORT:-3000}/mcp"
  fi
}

compose_profile_args() {
  [ "${EXPOSE_MODE:-private}" = "public" ] && echo "--profile caddy"
}
```

- [ ] **Step 4: 删除 `is_docker_mode`/`is_local_mode`/`detect_service_type`**

删除这三个函数的整段定义（原 105-124 行附近）。

- [ ] **Step 5: 校验**

Run: `bash -n lib/common.sh && echo OK`
Expected: `OK`

Run: `grep -nE 'is_docker_mode|is_local_mode|detect_service_type' lib/common.sh; echo "exit=$?"`
Expected: 无匹配，`exit=1`。

- [ ] **Step 6: Commit**

```bash
git add lib/common.sh
git commit -m "refactor: docker-only common.sh — exec health check, endpoint/profile helpers"
```

---

## Task 3: `cmd/deploy.sh` — 单一 Docker 向导 + 暴露方式

**Files:**
- Modify (重写): `cmd/deploy.sh`

**Interfaces:**
- Consumes: `step_llm`、`step_embedding`、`write_llm_env`、`write_embed_env_docker`、`write_git_env`、`step_git_sync`（保留 Docker 相关部分）；`gen_secret`、`wait_for_health`、`agent_endpoint`、`compose_profile_args`。
- Produces: 写出 `.env`（含 Global Constraints 的键），`docker compose build && up -d`，等待健康，打印端点。

- [ ] **Step 1: 删除 Local 全部内容**

删除 `detect_os`、`deploy_local`（整个函数），以及 `step_embedding` 中 Local 分支与 `write_embed_env_local`。文件末尾的模式选择改为直接调用 Docker 流程（见 Step 4）。`step_embedding` 简化为只保留 Docker 的 7 选项分支（去掉 `case "$1" in *Docker*)... *)` 外层判断，直接用 7-option 主体）。

- [ ] **Step 2: 在 Docker 向导加"暴露方式"步骤**

在原 Step 5（Server）之后、写 `.env` 之前插入暴露方式收集逻辑：

```bash
  # Step 6/6: Network exposure
  header "Step 6/6: Network Exposure"
  EXPOSE_CHOICE=$(prompt_select "How will gbrain be reached?" \
    "Private network (Tailscale/LAN, HTTP over encrypted network)" \
    "Public domain (Caddy + automatic HTTPS)")
  case "$EXPOSE_CHOICE" in
    1)
      EXPOSE_MODE="private"
      DOMAIN=""
      ACME_EMAIL=""
      local ts_ip=""
      ts_ip=$(tailscale ip -4 2>/dev/null | head -1 || true)
      GBRAIN_BIND_ADDR=$(prompt_text "Bind gbrain port to host address" "${ts_ip:-127.0.0.1}")
      ;;
    2)
      EXPOSE_MODE="public"
      GBRAIN_BIND_ADDR="127.0.0.1"
      DOMAIN=$(prompt_text "Domain (must resolve to this server)" "brain.example.com")
      ACME_EMAIL=$(prompt_text "Email for Let's Encrypt" "you@example.com")
      ;;
  esac
```

- [ ] **Step 3: 写 `.env` 增加暴露/备份键**

在原 `.env` 写入的 heredoc 里，Server 段后追加（备份口令自动生成）：

```bash
  BACKUP_PASSPHRASE_DEFAULT=$(gen_secret)
  cat >> .env <<EOF

# Network exposure
EXPOSE_MODE=${EXPOSE_MODE}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
GBRAIN_BIND_ADDR=${GBRAIN_BIND_ADDR}

# Backup
BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE_DEFAULT}
BACKUP_KEEP=7
EOF
```

- [ ] **Step 4: 用 profile 构建/启动 + 健康检查 + 端点输出**

把构建/启动段改为（合并 ollama 与 caddy profile）：

```bash
  source .env
  COMPOSE_ARGS=("--env-file" ".env")
  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && COMPOSE_ARGS+=("--profile" "ollama")
  [ "${EXPOSE_MODE}" = "public" ] && COMPOSE_ARGS+=("--profile" "caddy")

  info "Building images..."
  docker compose "${COMPOSE_ARGS[@]}" build
  info "Starting services..."
  docker compose "${COMPOSE_ARGS[@]}" up -d

  [ "${EMBED_PROVIDER:-}" = "ollama-docker" ] && {
    info "Pulling Ollama model: ${EMBED_MODEL}..."
    docker compose exec ollama ollama pull "${EMBED_MODEL}"
  }

  info "Waiting for gbrain to start..."
  if ! wait_for_health 120; then
    warn "gbrain did not respond within 120s. Check: gbrain.sh logs"
    exit 1
  fi

  echo ""
  echo -e "${GREEN}  gbrain is live!${NC}"
  echo ""
  echo -e "  MCP endpoint:    ${CYAN}$(agent_endpoint)${NC}"
  if [ "${EXPOSE_MODE}" = "public" ]; then
    echo -e "  Admin dashboard: ${CYAN}https://${DOMAIN}/admin${NC}"
  else
    echo -e "  Admin dashboard: ${CYAN}http://${GBRAIN_BIND_ADDR}:${GBRAIN_PORT}/admin${NC}"
    echo -e "  ${DIM}For HTTPS + MagicDNS over Tailscale, run on the host:${NC}"
    echo -e "  ${DIM}  tailscale serve --bg https / http://localhost:${GBRAIN_PORT}${NC}"
  fi
  echo ""
  echo -e "  Next: ${BOLD}gbrain.sh agents add <name>${NC}"
  echo ""
```

- [ ] **Step 5: 文件末尾改为直接进入 Docker 向导**

删掉"Docker / Local 二选一"的 `prompt_select`，main 段直接调用 `deploy_docker`（保留 `deploy_docker` 函数名与其 banner）。

- [ ] **Step 6: 校验**

Run: `bash -n cmd/deploy.sh && echo OK`
Expected: `OK`

Run: `grep -nE 'deploy_local|detect_os|write_embed_env_local|Local \(bare' cmd/deploy.sh; echo "exit=$?"`
Expected: 无匹配，`exit=1`。

- [ ] **Step 7: Commit**

```bash
git add cmd/deploy.sh
git commit -m "refactor: deploy.sh docker-only + network exposure step"
```

---

## Task 4: `cmd/agents.sh` — 上游 auth 机制

**Files:**
- Modify (重写): `cmd/agents.sh`

**Interfaces:**
- Consumes: `load_config`、`agent_endpoint`、`ok/info/warn/die`、`header`。
- Produces: `agents add <name>` 经容器 `gbrain auth create` 取 `gbrain_<hex>` token、存 `credentials/<name>.json`；`agents list` 直出 `gbrain auth list`；`agents remove <name>` 经 `gbrain auth revoke` + 删本地文件。

- [ ] **Step 1: 重写整个 case**

```bash
#!/usr/bin/env bash
# cmd/agents.sh — register/list/revoke agents via upstream `gbrain auth`
load_config

ACTION="${1:-list}"
shift 2>/dev/null || true
CREDS_DIR="credentials"

case "$ACTION" in
  list)
    header "Registered Agents (from gbrain)"
    docker compose exec -T gbrain gbrain auth list || warn "Could not reach gbrain. Is it running?"
    ;;
  add)
    NAME="${1:?Usage: gbrain.sh agents add <name>}"
    info "Creating access token for '${NAME}'..."
    OUT=$(docker compose exec -T gbrain gbrain auth create "$NAME" 2>&1) || die "auth create failed:\n${OUT}"
    TOKEN=$(printf '%s' "$OUT" | grep -oE 'gbrain_[A-Za-z0-9]+' | head -1)
    [ -n "$TOKEN" ] || die "Could not parse token from gbrain output:\n${OUT}"

    ENDPOINT=$(agent_endpoint)
    mkdir -p "$CREDS_DIR"
    cat > "${CREDS_DIR}/${NAME}.json" <<EOF
{
  "agent_name": "${NAME}",
  "token": "${TOKEN}",
  "endpoint": "${ENDPOINT}",
  "registered_at": "$(date -Iseconds)"
}
EOF
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Agent registered: ${NAME}"
    echo "══════════════════════════════════════════════════"
    echo ""
    echo "  Token:    ${TOKEN}"
    echo "  Endpoint: ${ENDPOINT}"
    echo "  Auth:     Authorization: Bearer ${TOKEN}"
    echo ""
    echo "  Saved to ${CREDS_DIR}/${NAME}.json — the token won't be shown again."
    echo ""
    ;;
  remove)
    NAME="${1:?Usage: gbrain.sh agents remove <name>}"
    info "Revoking '${NAME}' in gbrain..."
    docker compose exec -T gbrain gbrain auth revoke "$NAME" || warn "Revoke failed (token may not exist)."
    rm -f "${CREDS_DIR}/${NAME}.json"
    ok "Agent removed: ${NAME}"
    ;;
  *)
    die "Unknown agents action: $ACTION (use: list|add|remove)"
    ;;
esac
```

- [ ] **Step 2: 校验**

Run: `bash -n cmd/agents.sh && echo OK`
Expected: `OK`

Run: `grep -nE 'ADMIN_SECRET|/register' cmd/agents.sh; echo "exit=$?"`
Expected: 无匹配，`exit=1`（确认 admin-secret 兜底已彻底移除）。

- [ ] **Step 3: Commit**

```bash
git add cmd/agents.sh
git commit -m "fix(security): agents use gbrain auth create, drop admin-secret-as-token"
```

---

## Task 5: `cmd/backup.sh` + `cmd/restore.sh` — 加密 + 轮转

**Files:**
- Modify (重写): `cmd/backup.sh`
- Modify (重写): `cmd/restore.sh`

**Interfaces:**
- Consumes: `load_config`、`.env` 的 `POSTGRES_USER/DB`、`BACKUP_PASSPHRASE`、`BACKUP_KEEP`；`ok/info/warn/die`、`prompt_yesno`。
- Produces: `backups/gbrain-<ts>.tar.enc`（openssl AES-256 加密的 tar，内含 `gbrain.sql` + `brain-data.tar.gz` + `.env.backup`）；`backups/latest` 符号链接；保留最近 `BACKUP_KEEP` 份。restore 反向解密恢复。

- [ ] **Step 1: 重写 `cmd/backup.sh`**

```bash
#!/usr/bin/env bash
# cmd/backup.sh — encrypted, rotated backup (docker-only)
load_config

[ -n "${BACKUP_PASSPHRASE:-}" ] || die "BACKUP_PASSPHRASE not set in .env."

BACKUP_DIR="${1:-backups}"
KEEP="${BACKUP_KEEP:-7}"
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] Dumping PostgreSQL..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-gbrain}" "${POSTGRES_DB:-gbrain}" > "${WORK}/gbrain.sql"

echo "[2/3] Archiving brain data..."
docker compose exec -T gbrain tar czf - -C /root .gbrain > "${WORK}/brain-data.tar.gz" 2>/dev/null \
  || warn "brain data archive empty or gbrain not running"

cp .env "${WORK}/.env.backup"

echo "[3/3] Encrypting bundle..."
OUT="${BACKUP_DIR}/gbrain-${TS}.tar.enc"
tar czf - -C "$WORK" gbrain.sql brain-data.tar.gz .env.backup \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:"${BACKUP_PASSPHRASE}" -out "$OUT"

ln -sfn "gbrain-${TS}.tar.enc" "${BACKUP_DIR}/latest"

# Rotation: keep newest $KEEP
ls -1t "${BACKUP_DIR}"/gbrain-*.tar.enc 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old"
done

SIZE=$(du -h "$OUT" | cut -f1)
echo ""
ok "Backup: ${OUT} (${SIZE}, encrypted)"
echo -e "  Restore: ${BOLD}gbrain.sh restore ${OUT}${NC}"
echo -e "  ${DIM}Keeping newest ${KEEP}; off-host copy: scp ${OUT} <dest>${NC}"
```

- [ ] **Step 2: 重写 `cmd/restore.sh`**

```bash
#!/usr/bin/env bash
# cmd/restore.sh — decrypt + restore (docker-only)
load_config

[ -n "${BACKUP_PASSPHRASE:-}" ] || die "BACKUP_PASSPHRASE not set in .env."

ENC="${1:?Usage: gbrain.sh restore <backups/gbrain-*.tar.enc>}"
[ -f "$ENC" ] || die "Backup not found: ${ENC}"

echo -e "  ${YELLOW}This will REPLACE all gbrain data.${NC}"
prompt_yesno "Continue?" "N" || { echo "Aborted."; exit 0; }

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "[1/4] Decrypting..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass pass:"${BACKUP_PASSPHRASE}" -in "$ENC" \
  | tar xzf - -C "$WORK" || die "Decrypt failed (wrong passphrase?)."
[ -f "${WORK}/gbrain.sql" ] || die "Invalid backup bundle."

echo "[2/4] Stopping gbrain..."
docker compose stop gbrain

echo "[3/4] Restoring PostgreSQL..."
docker compose exec -T postgres psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
docker compose exec -T postgres psql -U postgres -d "${POSTGRES_DB:-gbrain}" \
  -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER:-gbrain};" 2>/dev/null || true
docker compose exec -T postgres psql -U "${POSTGRES_USER:-gbrain}" -d "${POSTGRES_DB:-gbrain}" < "${WORK}/gbrain.sql"

echo "[4/4] Restoring brain data..."
if [ -f "${WORK}/brain-data.tar.gz" ]; then
  docker compose start gbrain
  docker compose exec -T gbrain sh -c 'rm -rf /root/.gbrain && tar xzf - -C /root' < "${WORK}/brain-data.tar.gz" || true
  docker compose restart gbrain
else
  docker compose start gbrain
fi

echo ""
ok "Restore complete from: ${ENC}"
```

- [ ] **Step 3: 校验**

Run: `bash -n cmd/backup.sh cmd/restore.sh && echo OK`
Expected: `OK`

Run（无 Docker 也可跑的加解密往返自检）:
```bash
P=testpass; echo "hello-brain" > /tmp/_b.txt
tar czf - -C /tmp _b.txt | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:"$P" -out /tmp/_b.enc
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass pass:"$P" -in /tmp/_b.enc | tar xzf - -C /tmp/_r 2>/dev/null || mkdir -p /tmp/_r && openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass pass:"$P" -in /tmp/_b.enc | tar xzf - -C /tmp/_r
cat /tmp/_r/_b.txt
```
Expected: 输出 `hello-brain`（证明加密/解密/打包往返正确）。

- [ ] **Step 4: Commit**

```bash
git add cmd/backup.sh cmd/restore.sh
git commit -m "feat(backup): encrypted bundles + retention, docker-only restore"
```

---

## Task 6: `cmd/service.sh` / `logs.sh` / `status.sh` / `config.sh` — docker-only

**Files:**
- Modify: `cmd/service.sh`、`cmd/logs.sh`、`cmd/status.sh`、`cmd/config.sh`

**Interfaces:**
- Consumes: `load_config`、`agent_endpoint`、输出助手。
- Produces: 四个命令均只走 docker compose；status 显示暴露模式与端点。

- [ ] **Step 1: 重写 `cmd/service.sh`**

```bash
#!/usr/bin/env bash
# cmd/service.sh — start/stop/restart (docker-only)
ACTION="$1"
load_config
case "$ACTION" in
  start)   info "Starting gbrain..."; docker compose start gbrain; ok "Started." ;;
  stop)    info "Stopping gbrain..."; docker compose stop gbrain; ok "Stopped." ;;
  restart) info "Restarting gbrain..."; docker compose restart gbrain; ok "Restarted." ;;
  *) die "Unknown action: $ACTION (expected: start|stop|restart)" ;;
esac
```

- [ ] **Step 2: 重写 `cmd/logs.sh`**

```bash
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
```

- [ ] **Step 3: 重写 `cmd/status.sh`**

```bash
#!/usr/bin/env bash
# cmd/status.sh — service status (docker-only)
load_config
header "gbrain Status"

if docker compose ps gbrain 2>/dev/null | grep -q "Up"; then
  echo -e "  ${BOLD}Service:${NC}   ${GREEN}●${NC} running"
else
  echo -e "  ${BOLD}Service:${NC}   ${RED}●${NC} stopped"
fi

echo -e "  ${BOLD}Exposure:${NC}  ${EXPOSE_MODE:-private}"
echo -e "  ${BOLD}Port:${NC}      ${GBRAIN_PORT:-3000}"

if docker compose exec -T gbrain curl -sf http://localhost:3000/health >/dev/null 2>&1; then
  echo -e "  ${BOLD}Health:${NC}    ${GREEN}●${NC} healthy"
else
  echo -e "  ${BOLD}Health:${NC}    ${YELLOW}●${NC} unreachable"
fi

if [ "${EXPOSE_MODE:-private}" = "public" ]; then
  echo -e "  ${BOLD}Caddy:${NC}     $(docker compose ps caddy 2>/dev/null | grep -q Up && echo "${GREEN}● up${NC}" || echo "${RED}● down${NC}")"
fi

if [ -d credentials ]; then
  N=$(find credentials -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${BOLD}Agents:${NC}    ${N} local credential file(s)"
fi
echo -e "  ${BOLD}Endpoint:${NC}  $(agent_endpoint)"
echo ""
```

- [ ] **Step 4: 改 `cmd/config.sh` 去掉 local 分支**

`config view/get/set` 三处把 `if is_docker_mode; then ... else ...` 的双分支折叠为单一 `.env` 路径。`view` 改为：

```bash
  view|"")
    header "Current Configuration (.env)"
    grep -v '^#' .env | grep -v '^$' | while IFS='=' read -r key val; do
      case "$key" in
        *API_KEY|*PASSWORD|*SECRET|*TOKEN|*PASSPHRASE) val="${val:0:4}****" ;;
      esac
      printf "  ${CYAN}%-25s${NC} %s\n" "$key" "$val"
    done
    echo ""
    ;;
```

`get`：`grep "^${CONFIG_KEY}=" .env | cut -d= -f2-`。
`set`：`CONFIG_FILE=".env"` 后沿用原 sed 更新/追加逻辑（保留 macOS/Linux sed 分支）。结尾提示改为 `gbrain.sh restart`。

- [ ] **Step 5: 校验**

Run: `bash -n cmd/service.sh cmd/logs.sh cmd/status.sh cmd/config.sh && echo OK`
Expected: `OK`

Run: `grep -nE 'systemd|launchd|is_docker_mode|\.env\.local' cmd/service.sh cmd/logs.sh cmd/status.sh cmd/config.sh; echo "exit=$?"`
Expected: 无匹配，`exit=1`。

- [ ] **Step 6: Commit**

```bash
git add cmd/service.sh cmd/logs.sh cmd/status.sh cmd/config.sh
git commit -m "refactor: service/logs/status/config docker-only"
```

---

## Task 7: `cmd/test.sh` — 冒烟测试

**Files:**
- Modify: `cmd/test.sh`

**Interfaces:**
- Consumes: `load_config`、`.env`。
- Produces: 容器内 `/health`、`/mcp` 401、`auth create`→MCP initialize→`auth revoke` 全链路冒烟。

- [ ] **Step 1: 重写测试主体（保留 pass/fail 计分框架）**

保留文件头部 `set -uo pipefail`、`load_config`、`pass()/fail()`、`RESULTS` 框架与结尾汇总。把测试用例替换为：

```bash
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
```

- [ ] **Step 2: 校验**

Run: `bash -n cmd/test.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add cmd/test.sh
git commit -m "test: smoke tests via container exec + auth create flow"
```

---

## Task 8: 文档 — help / README / CLAUDE.md / AGENT.md

**Files:**
- Modify: `cmd/help.sh`、`README.md`、`CLAUDE.md`、`AGENT.md`

**Interfaces:**
- Produces: 文档与 docker-only/双暴露模式/新 agents 与备份命令一致。

- [ ] **Step 1: 改 `cmd/help.sh`**

删除 `deploy` 主题里的 `Equivalent to: ./deploy-docker.sh or ./deploy-local.sh` 行；`agents` 子命令说明去掉 `[scope]`（改为 `add <name>`）；`deploy` 描述改为 "Interactive Docker deployment wizard (public domain or private/Tailscale)"。

- [ ] **Step 2: 改 `README.md`**

更新：去掉 Local/裸机模式与"China-region servers"双模式表述；部署仅 Docker；新增"网络暴露：公网域名 / Tailscale 私网"小节；agents 注册示例改为 `gbrain.sh agents add <name>`（无 scope）；备份示例标注加密 + `BACKUP_PASSPHRASE` + 轮转。逐处替换 `http://<server>:port/mcp` 为按模式的 `https://<domain>/mcp` 或 `http://<bind>:port/mcp`。

- [ ] **Step 3: 改 `CLAUDE.md`**

按本次架构改写："Two deployment modes (Docker + Local)" → "Docker-only"。删除 Local path、systemd/launchd、`~/.gbrain-deploy/.env.local`、`is_docker_mode`/`detect_service_type` 等已删项的描述。更新 Architecture 树、Config flow、Environment variable groups（加 EXPOSE_MODE/DOMAIN/ACME_EMAIL/GBRAIN_BIND_ADDR/BACKUP_PASSPHRASE/BACKUP_KEEP）。更新 Common Commands 的 `agents add`（去 scope）与备份说明。移除上一版我加的 "Mode detection (.env presence)" 段（不再有双模式），替换为暴露模式说明。

- [ ] **Step 4: 改 `AGENT.md`**

同步：连接端点改为按暴露模式；token 获取方式改为 `gbrain.sh agents add <name>`（上游 `gbrain auth create`），删除 admin-secret 作为 agent token 的任何描述。

- [ ] **Step 5: 校验**

Run: `grep -rnE 'deploy-local|deploy-docker\.sh|\.env\.local|systemd|launchd|bare metal|裸机|admin.?secret.*token' README.md CLAUDE.md AGENT.md cmd/help.sh; echo "exit=$?"`
Expected: 仅剩有意保留的引用（理想为无匹配 `exit=1`）；逐条确认无遗留 Local/旧鉴权表述。

- [ ] **Step 6: Commit**

```bash
git add cmd/help.sh README.md CLAUDE.md AGENT.md
git commit -m "docs: align with docker-only + dual exposure + new auth/backup"
```

---

## Task 9: 全量校验与清理

**Files:**
- 只读检查；按需小修。

- [ ] **Step 1: 语法全过**

Run: `for f in gbrain.sh lib/*.sh cmd/*.sh scripts/entrypoint.sh; do bash -n "$f" || echo "FAIL: $f"; done; echo done`
Expected: 仅 `done`，无 `FAIL`。

- [ ] **Step 2: shellcheck（若安装）**

Run: `command -v shellcheck >/dev/null && shellcheck -S warning gbrain.sh lib/*.sh cmd/*.sh || echo "shellcheck not installed, skipped"`
Expected: 无 error 级问题（warning 酌情修）。

- [ ] **Step 3: 残留 Local/旧机制扫描**

Run: `grep -rnE 'is_local_mode|detect_service_type|deploy_local|\.env\.local|/register|GBRAIN_ADMIN_SECRET.*Bearer' lib cmd scripts gbrain.sh; echo "exit=$?"`
Expected: 无匹配，`exit=1`。

- [ ] **Step 4: compose 结构校验（若有 docker）**

Run: `cp .env.example .env.smoke 2>/dev/null; docker compose --env-file .env.example config -q && echo "compose OK" || echo "review compose manually"`
Expected: `compose OK`（或人工确认 YAML）。清理：`rm -f .env.smoke`。

- [ ] **Step 5: 最终提交（若 Step 1-4 有小修）**

```bash
git add -A && git commit -m "chore: final syntax + lint cleanup for docker-only refactor" || echo "nothing to commit"
```

---

## Self-Review（计划编写后自查结论）

- **Spec coverage：** 仅 Docker（T2-T7 删除全部 local）✓；两种暴露模式（T1 compose/caddy profile + T3 向导 + common `agent_endpoint`）✓；加密+轮转备份（T5）✓；agent 用 `gbrain auth create`（T4）✓；git token credential-store（T1 step5）✓；Dockerfile 固定 ref/不吞错（T1 step4）✓；健康检查经 exec（T2）✓；文档同步（T8）✓。
- **Placeholder：** 无 TBD/TODO；新代码均给出完整片段；机械删除给出精确目标与 grep 验证。
- **Type/接口一致：** `agent_endpoint`、`compose_profile_args`、`load_config(DEPLOY_MODE)`、`wait_for_health(max_wait)`、token 正则 `gbrain_[A-Za-z0-9]+`、`.env` 键名在各 Task 间一致。
- **已知人工依赖：** 完整运行时验证需要带 Docker（且 public 模式需真实域名）的主机——属 e2e，归入实施者手动执行，不阻塞代码层 `bash -n`/逻辑自查。
