# gbrain-deploy

> 在一台服务器上部署 [gbrain](https://github.com/garrytan/gbrain)，让多个 AI agent（Claude、OpenClaw、Hermes、Cursor……）共用同一个知识大脑。

---

## 一句话开始

```bash
# 服务器在国内 / 没有 Docker：
./deploy-local.sh

# 服务器在海外 / 已装 Docker：
./deploy-docker.sh
```

按提示回答几个问题，自动完成安装。部署完你会得到：

- 一个 MCP 地址，所有 agent 都能连
- 一个管理后台页面
- 一套 agent 接入配置模板

---

## 两种部署方式怎么选？

| | `deploy-local.sh` | `deploy-docker.sh` |
|---|---|---|
| **需要 Docker 吗** | 不需要 | 需要 |
| **适合什么服务器** | 国内服务器（不用拉 Docker 镜像） | 海外服务器、云主机 |
| **数据库** | 本机 PostgreSQL | Docker 容器内 PostgreSQL |
| **怎么管理服务** | systemd / launchd | docker compose |
| **要求** | 有 root 或 sudo 权限 | 装好 Docker + Compose |

选哪个都行，功能完全一样。

---

## 部署时会被问到什么？

两种方式问的问题基本相同：

### 1. 数据库

```
PostgreSQL 用户 [gbrain]:
PostgreSQL 密码 [自动生成]: ← 回车就行，会自动生成一个强密码
PostgreSQL 数据库名 [gbrain]:
```

### 2. AI 模型（用于知识提取、摘要、纠错）

```
LLM 提供商：
  1) OpenAI
  2) 自定义地址（OpenAI 兼容的都行，比如中转站、One API、LiteLLM……）
  3) 跳过，之后再说
```

选 2 的话可以填任意 OpenAI 兼容的 API 地址：

```
API 地址: https://your-api.com/v1
API Key: sk-xxx
模型名: gpt-4o
```

### 3. 词向量模型（用于搜索）

```
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

### 4. 服务端口和管理密码

```
HTTP 端口 [3000]:
管理密码 [自动生成]: ← 回车自动生成
```

### 5. 确认部署

脚本会显示一个配置汇总，确认后自动开始安装。

---

## 部署完成后

你会看到类似这样的输出：

```
╔══════════════════════════════════════════╗
  gbrain 已启动！
╚══════════════════════════════════════════╝

  MCP 地址:    http://192.168.1.100:3000/mcp
  管理后台:    http://192.168.1.100:3000/admin
```

### 接入 Agent

```bash
# 注册一个 agent，拿到连接凭证
./register-agent.sh claude-code "read write"
```

详细的接入步骤、各平台配置方式、对话示例，请看 **[AGENT.md](AGENT.md)**。

### 使用示例

部署完成后，Agent 就能直接读写你的知识库。比如用 Claude Code 对话：

```
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

### 本机部署（local）

```bash
# 查看状态
sudo systemctl status gbrain

# 重启
sudo systemctl restart gbrain

# 看日志
sudo journalctl -u gbrain -f

# 改配置后重启
vi ~/.gbrain-deploy/.env.local
sudo systemctl restart gbrain
```

macOS 用 launchctl 代替 systemctl，部署完会提示具体命令。

### Docker 部署

```bash
docker compose logs -f gbrain     # 看日志
docker compose restart gbrain     # 重启
docker compose down               # 停止
docker compose up -d              # 启动
```

---

## 备份和迁移（Docker 部署用 backup.sh，本机部署用 pg_dump）

```bash
# Docker 部署 — 一键备份
./backup.sh
# 恢复
./restore.sh backups/latest

# 本机部署 — 用 pg_dump
pg_dump -U gbrain gbrain > backup.sql
# 恢复
psql -U gbrain gbrain < backup.sql
```

迁移到新服务器：备份 → 复制到新机器 → 恢复 → 重新部署。

---

## 项目文件说明

```
gbrain-deploy/
├── deploy-local.sh          ← 本机部署（国内推荐）
├── deploy-docker.sh         ← Docker 部署
├── register-agent.sh        ← 注册新 Agent
├── backup.sh / restore.sh   ← 备份恢复（仅 Docker 部署）
├── docker-compose.yml       ← Docker 编排文件
├── Dockerfile               ← gbrain 容器镜像
├── scripts/entrypoint.sh    ← 容器启动脚本
├── .env.example             ← 配置模板（手动部署用）
├── AGENT.md                 ← Agent 接入指南（通用）
├── .gitignore
└── README.md                ← 你正在看的这个文件
```

---

## 常见问题

**Q: 国内服务器拉不到 Docker 镜像怎么办？**
用 `deploy-local.sh`，不需要 Docker。

**Q: 不想用 OpenAI，有国内替代吗？**
选「自定义地址」，填你的中转站或私有 API 地址即可。任何 OpenAI 兼容的 API 都行。

**Q: 词向量不想花钱？**
选 Ollama，完全本地运行，免费。先装 Ollama：`curl -fsSL https://ollama.com/install.sh | sh`，然后拉一个模型：`ollama pull nomic-embed-text`。

**Q: 想改配置怎么办？**
- 本机部署：编辑 `~/.gbrain-deploy/.env.local`，然后重启服务
- Docker 部署：编辑项目目录下的 `.env`，然后 `docker compose up -d`

**Q: 支持 macOS 吗？**
本机部署支持，会自动创建 launchd 服务。Docker 部署也支持。

---

## License

MIT. [gbrain](https://github.com/garrytan/gbrain) 本身也是 MIT 协议，由 Garry Tan 开发。
