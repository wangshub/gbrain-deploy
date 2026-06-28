# gbrain-deploy

> 在一台服务器上部署 [gbrain](https://github.com/garrytan/gbrain)，让多个 AI agent（Claude、OpenClaw、Hermes、Cursor……）共用同一个知识大脑。

---

## 一句话开始

```bash
./gbrain.sh deploy
```

按提示回答几个问题，自动完成安装。部署完你会得到：

- 一个 MCP 地址，所有 agent 都能连
- 一个管理后台页面
- 一套 agent 接入配置模板

---

## 网络暴露模式

部署时会询问你选择哪种网络暴露方式（写入 `.env` 的 `EXPOSE_MODE`）：

| | `public` 模式 | `private` 模式 |
|---|---|---|
| **适合场景** | 有公网域名的云服务器 | Tailscale / 内网 / 本地开发 |
| **HTTPS** | 自动（Let's Encrypt + Caddy） | 走内网/VPN 加密，或 `tailscale serve` |
| **需要什么** | 域名 + ACME 邮箱 | 无额外要求 |
| **MCP 端点** | `https://<domain>/mcp` | `http://<bind-addr>:<port>/mcp` |
| **管理后台** | `https://<domain>/admin` | `http://<bind-addr>:<port>/admin` |

- **public**：启用 Caddy compose profile + Let's Encrypt 自动 HTTPS，填入域名（`DOMAIN`）和邮箱（`ACME_EMAIL`）即可。
- **private**：不启 Caddy，gbrain 绑定到 `GBRAIN_BIND_ADDR`（默认 `127.0.0.1`，Tailscale 场景填 `100.x.x.x`），通过内网/WireGuard 走纯 HTTP。需要 HTTPS+MagicDNS 时可自行运行 `tailscale serve --bg https / http://localhost:<port>`。

---

## 部署时会被问到什么？

部署向导会依次问以下问题：

### 1. 数据库

```text
PostgreSQL 用户 [gbrain]:
PostgreSQL 密码 [自动生成]: ← 回车就行，会自动生成一个强密码
PostgreSQL 数据库名 [gbrain]:
```

### 2. AI 模型（用于知识提取、摘要、纠错）

```text
LLM 提供商：
  1) OpenAI
  2) 自定义地址（OpenAI 兼容的都行，比如中转站、One API、LiteLLM……）
  3) 跳过，之后再说
```

选 2 的话可以填任意 OpenAI 兼容的 API 地址：

```text
API 地址: https://your-api.com/v1
API Key: sk-xxx
模型名: gpt-4o
```

### 3. 词向量模型（用于搜索）

```text
词向量提供商：
  1) OpenAI
  2) 自定义地址（OpenAI 兼容）
  3) ZeroEntropy
  4) Voyage AI
  5) Ollama（本地运行，不需要 API Key）
  6) 跳过，之后再说
```

**选 Ollama 的话：** 完全本地运行，不需要任何 API Key。部署脚本会提示你先拉模型：

```bash
ollama pull nomic-embed-text
```

### 4. 网络暴露模式

```text
暴露模式：
  1) public  — 公网域名 + Caddy 自动 HTTPS
  2) private — 内网/Tailscale（纯 HTTP，绑定指定地址）
```

选 `public` 还需填：

```text
域名（如 gbrain.example.com）:
ACME 邮箱:
```

选 `private` 还需填（回车使用默认）：

```text
绑定地址 [127.0.0.1]: ← Tailscale 场景填 100.x.x.x
```

### 5. 服务端口和管理密码

```text
HTTP 端口 [3000]:
管理密码 [自动生成]: ← 回车自动生成
```

### 6. 确认部署

脚本会显示一个配置汇总，确认后自动开始安装。

---

## 部署完成后

你会看到类似这样的输出：

```text
╔══════════════════════════════════════════╗
  gbrain 已启动！
╚══════════════════════════════════════════╝

  # public 模式：
  MCP 地址:    https://your.domain/mcp
  管理后台:    https://your.domain/admin

  # private 模式：
  MCP 地址:    http://100.x.x.x:3000/mcp
  管理后台:    http://100.x.x.x:3000/admin
```

### 接入 Agent

```bash
# 注册一个 agent，拿到连接凭证（gbrain_... token，只显示一次）
./gbrain.sh agents add claude-code

# 查看已注册的 agents
./gbrain.sh agents list
```

详细的接入步骤、各平台配置方式、对话示例，请看 **[AGENT.md](AGENT.md)**。

### 使用示例

部署完成后，Agent 就能直接读写你的知识库。比如用 Claude Code 对话：

```text
你: 帮我查一下之前和 Bob 讨论过的项目方案

Claude Code: [调用 gbrain search]
  找到 3 条相关记录：
  1. "和 Bob 讨论 Acme 项目架构" — 选择了微服务方案...
  2. "Acme 项目技术选型" — 数据库用 PostgreSQL...

你: 记一下：明天下午 3 点和 Alice 开会，讨论 Q2 预算

Claude Code: [调用 gbrain capture]
  已保存到知识库。

你: Bob 投资了哪些公司？

Claude Code: [调用 gbrain graph-query]
  Bob 投资了：
  - Acme AI（种子轮，2024年1月）
  - Beta Corp（A轮，2024年3月）
```

---

## 日常管理

### 统一 CLI 命令

```bash
# 查看服务状态
./gbrain.sh status

# 查看日志
./gbrain.sh logs -f

# 重启服务
./gbrain.sh restart

# 停止/启动
./gbrain.sh stop
./gbrain.sh start

# 查看配置
./gbrain.sh config view

# 修改配置
./gbrain.sh config set GBRAIN_PORT 3001
./gbrain.sh restart  # 重启生效
```

### 手动管理 Docker（高级用户）

```bash
docker compose ps
docker compose logs -f gbrain
docker compose restart gbrain
docker compose down
docker compose up -d
```

---

## 备份和迁移

```bash
# 备份（生成 AES-256 加密的 .tar.enc 文件，口令来自 .env 的 BACKUP_PASSPHRASE）
./gbrain.sh backup
# 默认保留最近 7 份（BACKUP_KEEP），自动轮转

# 恢复（需要相同的 BACKUP_PASSPHRASE）
./gbrain.sh restore backups/gbrain-<timestamp>.tar.enc

# 迁移到新服务器：备份 → 复制到新机器 → 恢复 → 重新部署
```

---

## 项目文件说明

```text
gbrain-deploy/
├── gbrain.sh                ← 统一 CLI 入口（推荐）
├── lib/
│   └── common.sh            ← 共享函数库
├── cmd/
│   ├── deploy.sh            ← 部署向导
│   ├── status.sh            ← 状态查看
│   ├── logs.sh              ← 日志查看
│   ├── agents.sh            ← Agent 管理
│   ├── backup.sh            ← 备份
│   ├── restore.sh           ← 恢复
│   ├── config.sh            ← 配置管理
│   ├── service.sh           ← 服务控制
│   └── test.sh              ← 测试
├── scripts/
│   └── entrypoint.sh        ← Docker 容器启动脚本
├── docker-compose.yml       ← Docker 编排文件
├── Dockerfile               ← gbrain 容器镜像
├── .env.example             ← 配置模板（手动部署用）
├── AGENT.md                 ← Agent 接入指南
├── .gitignore
└── README.md                ← 你正在看的这个文件
```

---

## 常见问题

**Q: 不想用 OpenAI，有国内替代吗？**
选「自定义地址」，填你的中转站或私有 API 地址即可。任何 OpenAI 兼容的 API 都行。

**Q: 词向量不想花钱？**
选 Ollama，完全本地运行，免费。先装 Ollama：`curl -fsSL https://ollama.com/install.sh | sh`，然后拉一个模型：`ollama pull nomic-embed-text`。

**Q: 想改配置怎么办？**

```bash
./gbrain.sh config view          # 查看当前配置
./gbrain.sh config set KEY value # 修改
./gbrain.sh restart              # 重启生效
```

**Q: 支持 macOS 吗？**
支持 Docker Desktop for Mac，按正常 Docker 部署流程操作即可。

---

## License

MIT. [gbrain](https://github.com/garrytan/gbrain) 本身也是 MIT 协议，由 Garry Tan 开发。
