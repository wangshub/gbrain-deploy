# Agent 接入指南

> 让任何 AI Agent 连接到你的共享 gbrain 知识大脑。

---

## 第一步：注册凭证

每个 Agent 需要独立的凭证。在部署 gbrain 的服务器上运行：

```bash
./gbrain.sh agents add <agent名称>
```

底层调用上游 `gbrain auth create`，签发一次性 `gbrain_<hex>` token，存入 `credentials/<名称>.json`。

**示例：**

```bash
./gbrain.sh agents add claude-code
./gbrain.sh agents add openclaw
./gbrain.sh agents add monitor
```

注册完会输出 token（`gbrain_...`），保存好，只显示一次。在 Agent 配置里以 Bearer 方式使用：

```
Authorization: Bearer gbrain_...
```

---

## 第二步：选择接入方式

**MCP 端点地址**取决于部署时选择的网络暴露模式：

| 模式 | MCP 端点 |
|------|---------|
| `public`（公网域名） | `https://your.domain/mcp` |
| `private`（Tailscale/内网） | `http://<bind-addr>:<port>/mcp` |

根据你用的 Agent 类型，选一种：

### 方式 A：MCP HTTP（推荐）

适用于：**Claude Code、Cursor、Windsurf、ChatGPT、Perplexity** 等支持 MCP 的客户端。

在 Agent 的配置文件里加上：

```json
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "https://your.domain/mcp",
      "headers": {
        "Authorization": "Bearer gbrain_..."
      }
    }
  }
}
```

**各客户端的配置文件位置：**

| Agent | 配置文件 |
|-------|---------|
| Claude Code（当前项目） | 项目目录 `.claude/settings.json` |
| Claude Code（全局） | `~/.claude/settings.json` |
| Cursor | 设置 → MCP → Add Server |
| Windsurf | 设置 → MCP Servers |
| 其他 MCP 客户端 | 查看其文档中的 MCP 配置方式 |

### 方式 B：Skillpack（OpenClaw / Hermes）

适用于：**OpenClaw、Hermes** 等 gbrain 原生支持的 Agent 平台。

在 Agent 所在的机器上：

```bash
# 1. 安装 gbrain CLI
bun install -g github:garrytan/gbrain

# 2. 指向共享服务器（URL 按暴露模式填写）
export GBRAIN_MCP_URL=https://your.domain/mcp   # public 模式
# 或
# export GBRAIN_MCP_URL=http://100.x.x.x:3000/mcp  # private 模式
export GBRAIN_MCP_TOKEN=gbrain_...

# 3. 安装 skillpack（43+ 技能，Agent 自动识别）
gbrain skillpack scaffold --all

# 4. 验证连接
gbrain doctor
```

把环境变量写到 Agent 的启动配置里，确保重启后仍然生效。

### 方式 C：CLI 瘦客户端

适用于：**任何能运行命令行的环境**，比如脚本、CI/CD、定时任务。

```bash
bun install -g github:garrytan/gbrain

export GBRAIN_MCP_URL=https://your.domain/mcp   # public 模式（或 http://...:<port>/mcp）
export GBRAIN_MCP_TOKEN=gbrain_...

# 搜索
gbrain search "谁在 Acme AI 工作"

# 写入
gbrain capture "今天和 Bob 讨论了新项目的架构方案"

# 查询知识图谱
gbrain graph-query people/bob --depth 2
```

### 方式 D：Webhook

适用于：**Zapier、IFTTT、Apple Shortcuts、自定义脚本** 等非 MCP 环境。

```bash
curl -X POST https://your.domain/ingest \
  -H "Authorization: Bearer gbrain_..." \
  -H "Content-Type: text/markdown" \
  -d "# 标题

内容写在这里..."
```

---

## 第三步：验证连接

```bash
# 测试服务是否在线（URL 按暴露模式填写）
curl https://your.domain/health          # public 模式
# 或
curl http://100.x.x.x:3000/health       # private 模式

# 在 Agent 中试试搜索
# （如果接入了 Claude Code，直接对话即可）
```

---

## 连上之后能做什么？

| 操作 | 说明 |
|------|------|
| `search` | 混合搜索（向量 + 关键词 + 知识图谱） |
| `capture` | 快速捕获一条想法或笔记 |
| `put_page` / `get_page` | 读写知识页面 |
| `graph_query` | 知识图谱查询（如：Bob 投资了哪些公司？） |
| `think` | 基于时间线的事实问答 |
| `find_trajectory` | 查询某实体随时间的变化轨迹 |

这些操作通过 MCP 协议自动暴露给 Agent——接上就能用，不需要额外配置。

---

## 接入示例

以下是一个完整的「注册 → 配置 → 使用」流程，以 Claude Code 为例：

```bash
# 1. 在服务器上注册
./gbrain.sh agents add my-claude
# 输出: token = gbrain_abc123...

# 2. 在本机配置（写入项目的 .claude/settings.json）
cat > .claude/settings.json <<EOF
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "https://your.domain/mcp",
      "headers": {
        "Authorization": "Bearer gbrain_abc123..."
      }
    }
  }
}
EOF

# 3. 直接和 Claude Code 对话
# Claude Code 会自动调用 gbrain 的 MCP 工具
```

**对话示例：**

```
你: 帮我查一下之前和 Bob 讨论过的项目方案

Claude Code: [自动调用 gbrain search "Bob 项目方案"]
  找到 3 条相关记录：
  1. "2024-03-15 和 Bob 讨论 Acme 项目架构" — 选择了微服务方案...
  2. "2024-03-20 Acme 项目技术选型" — 数据库用 PostgreSQL...
  ...
```

```
你: 记一下：明天下午 3 点和 Alice 开会，讨论 Q2 预算

Claude Code: [自动调用 gbrain capture]
  已保存到知识库。
```

```
你: Bob 投资了哪些公司？

Claude Code: [自动调用 gbrain graph-query people/bob]
  根据知识图谱，Bob 投资了：
  - Acme AI（种子轮，2024年1月）
  - Beta Corp（A轮，2024年3月）
```
