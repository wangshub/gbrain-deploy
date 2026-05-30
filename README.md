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

## 两种部署方式怎么选？

部署时会自动询问你选择哪种模式：

| | Local 模式 | Docker 模式 |
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

### 4. 服务端口和管理密码

```text
HTTP 端口 [3000]:
管理密码 [自动生成]: ← 回车自动生成
```

### 5. 确认部署

脚本会显示一个配置汇总，确认后自动开始安装。

---

## 部署完成后

你会看到类似这样的输出：

```text
╔══════════════════════════════════════════╗
  gbrain 已启动！
╚══════════════════════════════════════════╝

  MCP 地址:    http://192.168.1.100:3000/mcp
  管理后台:    http://192.168.1.100:3000/admin
```

### 接入 Agent

```bash
# 注册一个 agent，拿到连接凭证
./gbrain.sh agents add claude-code "read write"

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

### 手动管理服务（高级用户）

**本机部署（systemd）：**

```bash
sudo systemctl status gbrain
sudo systemctl restart gbrain
sudo journalctl -u gbrain -f
```

**本机部署（macOS launchd）：**

```bash
launchctl list | grep gbrain
launchctl unload ~/Library/LaunchAgents/com.gbrain.server.plist
launchctl load ~/Library/LaunchAgents/com.gbrain.server.plist
tail -f ~/Library/Logs/gbrain.log
```

**Docker 部署：**

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
# 备份（Docker 和 Local 模式都支持）
./gbrain.sh backup

# 恢复
./gbrain.sh restore backups/latest

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

**Q: 国内服务器拉不到 Docker 镜像怎么办？**
选 Local 模式，不需要 Docker。

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
支持。Local 模式会自动创建 launchd 服务。Docker 模式也支持。

---

## License

MIT. [gbrain](https://github.com/garrytan/gbrain) 本身也是 MIT 协议，由 Garry Tan 开发。
