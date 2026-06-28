# gbrain-deploy 重构设计：Docker-only · Caddy 自动 HTTPS · 加密备份

日期：2026-06-28
状态：待评审

## 目标

把 gbrain-deploy 重构为**简洁、易部署/使用/备份、可安全公网部署**的工具。三项已确认的范围决策：

1. **仅保留 Docker 部署模式**（删除 Local/裸机模式）
2. **两种网络暴露模式**：公网域名（Caddy 自动 HTTPS）/ 私网（Tailscale 等，纯 HTTP 靠 WireGuard 加密）
3. **备份加密 + 保留轮转**

网络暴露的两种模式都安全：公网用 Let's Encrypt TLS；Tailscale 流量本身是 WireGuard 端到端加密，纯 HTTP 即可。Caddy 从"默认内置"降级为"公网模式按需启用"（compose profile，类似 ollama）。不单独做纯 LAN IP 自签模式。

## 当前问题（重构动机）

- **安全（公网硬伤）**：`agents add` 在注册失败时把 admin 密钥当作 agent token 发出去（`cmd/agents.sh:43-55`）；全程纯 HTTP 无 TLS，Bearer token 明文传输；git sync 把 PAT 明文拼进 remote URL 落到 `.git/config`。
- **不简洁**：Docker + Local 双模式让 `deploy.sh`（726 行）几乎所有逻辑写两遍——embedding 向导 7 vs 6 选项、两套 env writer、两套备份/恢复、systemd/launchd/manual 三种服务管理。
- **备份**：明文 SQL + 含密钥 `.env`，无加密、无轮转。

## 上游事实（已核实，决定实现正确性）

- HTTP transport 强制 Bearer 鉴权，fail-closed；仅 `/health` 与 CORS 预检放行。
- Bearer token 正确签发方式：`gbrain auth create <name>` → 一次性打印 `gbrain_<64hex>`；`gbrain auth list`；`gbrain auth revoke <name>`。
- `auth create` **不接受 `read/write` scope**（那是 OAuth client 概念），只有 `--takes-holders`（可见性，默认 `world`）。现有 wrapper 的 "scope read write" 参数是误导，应删除。
- gbrain `serve --http` 硬依赖 Postgres（与当前 pgvector 一致）。

## 目标架构

```
gbrain.sh                 CLI 入口（dispatch 不变，去掉模式分支）
lib/common.sh             helpers；删除 is_docker_mode/is_local_mode/
                          detect_service_type/get_external_host 改造
cmd/
  deploy.sh               单一 Docker 路径 + 域名/Caddy 步骤（~250 行，原 726）
  status.sh               docker-only
  logs.sh                 docker-only（gbrain + caddy）
  service.sh              docker-only start/stop/restart
  agents.sh               重写：gbrain auth create/list/revoke（compose exec）
  backup.sh               加密打包 + 保留轮转
  restore.sh              解密 + 恢复
  config.sh               docker-only
  test.sh                 经容器内/HTTPS 的冒烟测试
  help.sh                 更新文案
docker-compose.yml        postgres + gbrain + caddy(profile) + ollama(profile)
Caddyfile                 反代模板（{$DOMAIN} → gbrain:3000），仅公网模式用
Dockerfile                固定 ref、不吞构建错误
scripts/entrypoint.sh     git token 用 credential store，不入 remote URL
.env.example              新增 EXPOSE_MODE / DOMAIN / ACME_EMAIL /
                          GBRAIN_BIND_ADDR / BACKUP_PASSPHRASE
```

`.gitignore` 已覆盖 `.env`/`credentials/`/`backups/`，无需改。

## 关键变更

### 1. 仅 Docker（最大简化）
删除 `deploy_local`（~330 行）、`detect_os`、bun/PostgreSQL 自动安装、systemd/launchd/manual 分支。`load_config` 只读 `.env`；删除 `is_local_mode` 等模式探测。所有 cmd 去掉 local 分支。

### 2. 网络暴露：两种模式
deploy 向导新增"暴露方式"步骤，写入 `.env` 的 `EXPOSE_MODE=public|private`。

**公网域名模式（`public`）**
- 启用 compose `caddy` profile：`caddy` 服务监听 80/443，卷 `caddy_data`/`caddy_config` 持久化证书，反代 `{$DOMAIN}` → `gbrain:3000`。
- `gbrain` 服务**不发布主机端口**，只在内网可达；容器内 `--bind 0.0.0.0`。
- 向导收集 `DOMAIN` + `ACME_EMAIL`。
- 对外端点：`https://<domain>/mcp`、`https://<domain>/admin`。

**私网模式（`private`，含 Tailscale/LAN）**
- 不起 Caddy。`gbrain` 发布端口但**绑定到指定地址**：compose `ports: "${GBRAIN_BIND_ADDR:-127.0.0.1}:${GBRAIN_PORT}:3000"`。
- 向导询问绑定地址：若主机 `tailscale ip -4` 可用，默认填检测到的 tailnet IP（100.x）；否则默认 `127.0.0.1`。
- 靠 WireGuard/内网加密，纯 HTTP。端点 `http://<bind-addr>:<port>/mcp`。
- 需要真证书 + MagicDNS 名时，部署完成后文档/输出提示一行：
  `tailscale serve --bg https / http://localhost:<port>`（用户自行执行，不自动化）。

**两模式通用**
- 健康检查统一用 `docker compose exec -T gbrain curl -sf localhost:3000/health`（不依赖 DNS/证书/主机端口），替代原 `curl localhost:port`。

### 3. Agent 鉴权修正（用上游真实机制）
- `agents add <name>` → `docker compose exec -T gbrain gbrain auth create <name>`，解析 `gbrain_...` token，存 `credentials/<name>.json`（已 gitignore）。端点按 `EXPOSE_MODE` 生成：public → `https://<domain>/mcp`；private → `http://<bind-addr>:<port>/mcp`。
- `agents list` → `gbrain auth list`（DB 实时，替代读本地 JSON）。
- `agents remove <name>` → `gbrain auth revoke <name>` + 删本地 cred 文件。
- **彻底删除 admin-secret 兜底路径**。删除误导的 `read/write` scope 入参（如需保留可见性控制，映射到 `--takes-holders`，默认 `world`）。

### 4. 加密备份 + 轮转
- `backup.sh`：SQL dump + brain 卷 tar + `.env` → 单一 tarball → 加密。
  - 加密优先 `age`（口令来自 `.env` 的 `BACKUP_PASSPHRASE` 或交互输入）；无 `age` 时回退 `openssl enc -aes-256-cbc -pbkdf2 -salt`。
  - 产物：`backups/gbrain-<ts>.tar.age`（或 `.tar.enc`）。
  - 轮转：默认保留最近 7 份（`--keep N` 可调），清理更早的。`latest` 符号链接。
  - 明文中间文件写入 `chmod 700` 临时目录，结束即删除。
- `restore.sh`：解密 → 解包 → 恢复 SQL + brain 卷。

### 5. 安全加固（小项）
- `entrypoint.sh` git sync：token 写入 `git credential-store`（`chmod 600`），remote URL 不含 token；不再 `sed` 拼进 URL。
- `Dockerfile`：默认 `GBRAIN_REF` 固定到某个发布 tag（而非 `master`）；删除 `bun run build 2>/dev/null; true` 的错误吞咽。
- admin bootstrap token 保留，但文档明确其为管理员专用，不用于 agent。

## 验证

- `for f in gbrain.sh lib/*.sh cmd/*.sh scripts/entrypoint.sh; do bash -n "$f"; done` 全过。
- `gbrain.sh test` 更新：容器内 `/health` ok；`/mcp` 无 token 返回 401；`auth create` 临时 token → MCP initialize 成功 → revoke。
- 手动：在带域名的测试主机跑一遍 `deploy`，确认 Caddy 签发证书、`https://<domain>/mcp` 可用。

## 不做（YAGNI）

- 多主机/集群、Vault 等密钥管理、备份自动异地上传（仅文档说明用 scp/rsync 拷走 `backups/`）。
- 不保留 Local 模式的任何兼容层。
