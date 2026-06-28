<div align="center">

# 🔌 Agent 接入指南

**把任意 AI Agent 连到你的共享 gbrain 知识大脑**

[← 回到 README](README.md) · [🔑 注册凭证](#-第一步注册凭证) · [🔗 接入方式](#-第二步接入) · [🧰 能做什么](#-连上之后能做什么)

</div>

---

## 🔑 第一步:注册凭证

每个 agent 用一份**独立、可单独吊销**的凭证。在部署 gbrain 的服务器上运行:

```bash
./gbrain.sh agents add claude-code
```

底层调用上游 `gbrain auth create`,签发一次性 `gbrain_<hex>` token(**只显示一次**,保存在 `credentials/claude-code.json`)。

```bash
./gbrain.sh agents list            # 查看已注册的 agents
./gbrain.sh agents remove <name>   # 吊销(调上游 gbrain auth revoke)
```

> 凭证以 Bearer 方式使用:`Authorization: Bearer gbrain_...`

**MCP 端点地址**取决于部署时选的[网络暴露模式](README.md#-网络暴露模式):

| 模式 | MCP 端点 |
|---|---|
| 🌍 `public`（公网域名） | `https://<域名>/mcp` |
| 🔒 `private`（Tailscale/内网） | `http://<bind-addr>:<port>/mcp` |

---

## 🔗 第二步:接入

### 方式 1 — `gbrain connect`（推荐:一条命令自动配置）

适用:**Claude Code、Codex、Perplexity**,以及任何 `generic` MCP 客户端。在 agent 所在的机器上:

```bash
# 装好 gbrain CLI
bun install -g github:garrytan/gbrain

# 一条命令接入(URL 是位置参数,按暴露模式填写)
gbrain connect https://<域名>/mcp \
  --token gbrain_... \
  --agent claude-code \    # 可选:claude-code | codex | perplexity | generic
  --install \              # 顺便安装大脑提供的 skillpack
  --yes
```

它会自动把 MCP 配置写进对应客户端。私网模式把 URL 换成 `http://<bind-addr>:<port>/mcp`。

> token 也可改用环境变量 **`GBRAIN_REMOTE_TOKEN`** 提供(URL 仍作为位置参数传入)。

### 方式 2 — 手动 MCP HTTP 配置

适用:**Cursor、Windsurf**,或任何 `gbrain connect` 未直接支持、但支持 MCP 的客户端。在客户端的 MCP 配置里加一段(Claude Code 用 `claude mcp add` 或项目根的 `.mcp.json`;Cursor 在 设置 → MCP):

```json
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "https://<域名>/mcp",
      "headers": { "Authorization": "Bearer gbrain_..." }
    }
  }
}
```

> 私网模式把 `url` 换成 `http://<bind-addr>:<port>/mcp`。

### 方式 3 — Webhook（非 MCP 环境）

适用:**Zapier、Apple Shortcuts、自定义脚本** 等。直接把 markdown POST 到 `/ingest`:

```bash
curl -X POST https://<域名>/ingest \
  -H "Authorization: Bearer gbrain_..." \
  -H "Content-Type: text/markdown" \
  -d "# 标题

内容写在这里..."
```

> 私网模式把地址换成 `http://<bind-addr>:<port>/ingest`。

---

## ✅ 验证连接

```bash
curl https://<域名>/health              # public 模式
curl http://<bind-addr>:<port>/health   # private 模式
# 返回内容包含 "ok" 即表示服务在线
```

接了 Claude Code 的话,直接对话让它搜一下知识库,就能验证工具是否生效。

---

## 🧰 连上之后能做什么

Agent 通过 MCP 协议自动获得这些工具,**接上即用、无需额外配置**:

| 工具 | 说明 |
|---|---|
| `search` / `query` | 混合检索(向量 + 关键词 + RRF);`query` 支持文本/图片路由 |
| `put_page` / `get_page` | 读写知识页面(markdown + frontmatter) |
| `list_pages` | 按条件列出/筛选页面 |
| `think` | 跨页面 + 观点 + 图谱的多跳综合问答 |
| `traverse_graph` / `get_links` / `get_backlinks` | 知识图谱遍历、正向/反向链接 |
| `add_tag` / `get_tags` / `add_link` | 标签与页面链接管理 |
| `takes_search` / `takes_list` | 检索"观点/预测"类条目(takes) |

> 这是常用子集。完整且随版本演进的工具列表以上游 [gbrain](https://github.com/garrytan/gbrain) 为准。

---

## 💬 接入示例（Claude Code）

```bash
# 1. 服务器上注册,拿到 token
./gbrain.sh agents add my-claude        # 输出 token = gbrain_abc123...

# 2. 本机一条命令接入
gbrain connect https://<域名>/mcp --token gbrain_abc123... --agent claude-code --yes

# 3. 直接对话,Claude Code 会自动调用 gbrain 的 MCP 工具
```

**对话示例:**

```text
你: 帮我查之前和 Bob 讨论过的项目方案
Claude Code: [search "Bob 项目方案"]
  1. "和 Bob 讨论 Acme 项目架构" — 选了微服务方案…
  2. "Acme 项目技术选型" — 数据库用 PostgreSQL…

你: 记一下:明天 15:00 和 Alice 开会,讨论 Q2 预算
Claude Code: [put_page] 已保存到知识库。

你: Bob 投资了哪些公司?
Claude Code: [traverse_graph people/bob]
  - Acme AI(种子轮,2024-01)
  - Beta Corp(A 轮,2024-03)
```

---

<div align="center"><sub>注册 → 一条命令接入 → 直接对话。部署细节见 <a href="README.md">README</a> 🧠</sub></div>
