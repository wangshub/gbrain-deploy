# 教程：从零搭建你的个人 AI 智能体 + 大脑

完成本教程后，你将拥有一个运行在自己控制的服务器上的 AI 智能体，通过 Telegram 与你对话，并拥有一个能记住你告诉它一切的大脑。全程约两小时，每月持续花费 $100 到 $150。

这是如果今天从零搭建整个技术栈我会选择的安装方案。我在与一位合作伙伴的安装过程中做了实时记录（我们用 Granola 录屏，因为"这对普通人来说已经太复杂了"）。本教程是那次会话的整理版本。

> "这就是 Apple I，我们只是在焊面包板而已。"

如果你只想要**大脑层**（不需要智能体、不需要 Telegram，只把 gbrain 作为你已有的 MCP 客户端的记忆），请跳到 INSTALL.md 中的 [CLI 独立安装](../INSTALL.md#2-cli-standalone)。如果你想将整个智能体**与团队共享**，请阅读[公司大脑教程](company-brain.md)。本教程是个人、全栈、通过 Telegram 对话的路径。

---

## 你要构建什么

一个个人 AI 智能体，包含四个部分：

- **大脑**（git 仓库）。你的知识库，持续摄取和增长。
- **运行框架**（通过 AlphaClaw 的 OpenClaw）。为 LLM 提供工具、记忆和集成的运行时。
- **聊天界面**（Telegram）。你与它对话的方式。
- **技能**（通过 GBrain 安装 60+）。智能体可以调用的可复用能力。

架构：

```
Telegram → AlphaClaw（运行框架）→ OpenClaw（智能体）→ GBrain（知识/技能）→ Supabase（嵌入/搜索）
```

Git 仓库是系统的记录源。整个系统默认就是多人协作的：任何接入仓库的智能体都能工作。冲突通过 git 解决。

---

## 前置条件

| 要求 | 原因 |
|---|---|
| GitHub 账号（组织或个人） | 用于存储智能体 + 大脑的两个仓库 |
| Render 账号 | 用于托管智能体运行时 |
| Telegram 账号 | 用于与智能体对话 |
| API 密钥：至少 OpenAI、Anthropic | 嵌入 + Claude 模型 |
| 每月约 $100 到 $150 | Render Pro + Supabase + API 使用费 |

---

## 第 1 步：创建两个 GitHub 仓库

你需要两个仓库，不是一个。

1. **工作区仓库。** 智能体配置、技能、记忆、定时任务。示例名称：`your-org/myagent`。私有。
2. **大脑仓库。** 知识库、人物页面、会议笔记，智能体读写的所有内容。示例名称：`your-org/myagent-brain`。私有。

```
GitHub → New Repository → your-org/myagent           (工作区)
GitHub → New Repository → your-org/myagent-brain     (大脑)
```

两个仓库都从空开始。GBrain 会在首次安装时用默认结构填充大脑仓库。

---

## 第 2 步：生成细粒度 Personal Access Token

GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens。

- **名称：** `myagent-token`
- **过期时间：** 1 年（或可用的话选择永不过期）
- **仓库访问权限：** 仅选择这两个仓库
- **权限：** 对两个仓库的读取和写入权限（Contents、Metadata、Pull requests）

GitHub 的细粒度 PAT 界面很不好用。创建仓库后可能需要重新加载页面才能在选择器中看到它们。这是整个设置中最痛苦的部分。坚持过去。

保存这个 token。AlphaClaw 设置时需要用到。

---

## 第 3 步：创建 Telegram 机器人

1. 打开 Telegram，给 [@BotFather](https://t.me/BotFather) 发消息
2. 发送 `/newbot`
3. 为你的机器人命名（随意）
4. 获取机器人 token
5. 保存它。AlphaClaw 设置时需要用到。

---

## 第 4 步：通过 AlphaClaw 在 Render 上部署

AlphaClaw 是管理 OpenClaw 部署的设置框架。

1. 访问 [alphaclaw.com](https://alphaclaw.com)
2. 输入你的**工作区仓库**（不是大脑仓库）：`your-org/myagent`
3. 如果仓库已存在，选择 "Use existing"
4. 输入第 2 步的 GitHub PAT
5. 输入第 3 步的 Telegram 机器人 token
6. 部署

Render 会构建一个包含运行框架的 Docker 容器。首次部署大约需要 5 分钟。

**内存很重要。** 如果安装过程中内存不足，升级到 Render Pro。基础套餐对 GBrain + OpenClaw 来说太小了。我的生产实例运行 48 核和 64GB 内存（每月约 $1,500），但这对新安装来说太过了。Pro 套餐（每月 $85）是最低可行配置。

---

## 第 5 步：添加提供商 API 密钥

在 AlphaClaw UI（Providers 标签页）中：

- **OpenAI API Key。** 如果你使用 OpenAI 提供商，这是嵌入所需的。
- **Anthropic API Key。** Claude 所需（智能体对话使用的主模型）。
- **Perplexity API Key。** 可选，用于网页搜索。
- **Voyage API Key。** 可选，OpenAI 嵌入的替代方案。
- **ZeroEntropy API Key。** 推荐。GBrain 默认使用 ZeroEntropy 作为嵌入器和重排序器，因为它比 OpenAI 快约 2 倍，便宜约 2.6 倍。

你可以在多个智能体之间使用相同的密钥。

---

## 第 6 步：安装 GBrain

OpenClaw 运行后：

```bash
gbrain install
```

这会安装：

- 约 60 个技能
- 约 9 个技能包
- 默认大脑结构
- MCP 服务器配置
- Supabase 连接（用于嵌入和搜索）

GBrain 用默认目录结构、技能文件和配置填充大脑仓库。从这时起，智能体拥有了可用的记忆和所有技能的访问权限。

---

## 第 7 步：设置 Supabase（嵌入和搜索）

GBrain 使用 Supabase 进行大规模向量嵌入和全文搜索。我踩过三个设置的坑。按以下顺序操作。

### 7a. 创建项目并启用 pgvector

1. 在 [supabase.com](https://supabase.com) 创建 Supabase 项目。选择离你的 Render 主机较近的区域。
2. 在 Supabase 控制台，进入 **Database → Extensions**。
3. 找到 `vector`（pgvector 扩展）并开启。

跳过这一步，每次 GBrain 尝试创建 schema 时嵌入写入都会失败并报 "type vector does not exist"。pgvector 是存储嵌入的关键；没有它 schema 迁移会拒绝运行。在 UI 中只需 5 秒；忘了的话要调试一小时。

### 7b. 使用连接池连接串，不要用直连串

在 **Project Settings → Database → Connection string** 中，Supabase 显示两个选项。它们看起来几乎一样。用对的那个。

- **直连**（端口 5432）。直接连接到 Postgres 实例。仅支持 IPv6。如果你的 Render 主机没有 IPv6 出站（大多数默认没有），会连接失败。
- **连接池**（端口 6543，主机名以 `aws-0-...pooler.supabase.com` 开头）。通过 Supabase 的 pgbouncer 连接。支持 IPv4。能承受并行工作者的连接风暴。

你需要的是**连接池**连接串。格式如下：

```
postgresql://postgres.YOUR-PROJECT:YOUR-PASSWORD@aws-0-us-west-1.pooler.supabase.com:6543/postgres
```

通过以下命令配置：

```bash
gbrain config set database_url "postgresql://postgres.YOUR-PROJECT:YOUR-PASSWORD@aws-0-us-west-1.pooler.supabase.com:6543/postgres"
```

### 7c. 如果主机仅支持 IPv4，购买 IPv4 插件

即使使用连接池，某些 Supabase 区域和某些 Render 套餐仍会遇到 IPv6 解析问题。如果你的 `gbrain doctor` 显示连接失败，错误信息提到 "network unreachable" 或连接时一直挂起，你需要 Supabase 的 **IPv4 插件**。

在 Supabase 控制台，**Project Settings → Add-ons → IPv4 address**。约每月 $4。开启后等待一分钟，重试连接。这个问题在多次安装中困扰过我，后来我学会了直接提前购买。

### 7d. 验证连接

```bash
gbrain doctor
```

schema、连接性、pgvector 扩展、嵌入提供商都应该是绿色对勾。如果任何一个是黄色，消息会告诉你踩了哪个坑（以及应该回顾 7a / 7b / 7c 中的哪一个）。

### 运维提示

Supabase 通常是扩展瓶颈，而不是 CPU 或 LLM 调用。如果你在进行大量摄取（邮件、日历、Slack 流入），尽早将数据库实例从小升级到大。不要等小实例撑不住；症状（静默插入失败、同步超时、嵌入回填停滞）看起来像不同的 bug，但实际上是同一个问题。

---

## 第 8 步：验证并聊天

1. 打开 Telegram
2. 给你的机器人发消息
3. 它应该使用 OpenClaw + GBrain 回复

发送一条测试消息。如果它回复时具有上下文感知能力并能搜索大脑，你就上线了。

---

## 架构说明

### Git 作为记录源

大脑仓库就是大脑。任何能读写 git 仓库的智能体都可以参与。这使得架构天生支持多人协作：多个智能体可以共享一个大脑，处理不同部分，并通过 git 解决冲突。

### 瘦客户端 vs 胖客户端

- **胖客户端**（我的生产设置）。OpenClaw + AlphaClaw + GBrain + 200 个定时任务 + 邮件处理 + Slack + 日历。每月约 $1,500。实时处理所有内容。
- **瘦客户端**（本教程构建的）。OpenClaw + GBrain + Telegram。每月约 $85。对话驱动、按需使用。

GBrain 的目标是让瘦客户端和胖客户端一样强大。大多数用户会从瘦客户端开始并逐步扩展。

### MCP 服务器

GBrain 暴露了一个 Model Context Protocol 服务器，支持智能体间通信和与外部系统集成。这是你添加对产品 API、数据库或其他服务读写访问的方式。

### 大脑共享

大脑通过 git 共享。我的主智能体可以通过向另一个智能体的仓库推送内容来填充它的大脑。MCP 层支持跨智能体大脑查询。只需推送到 git 仓库，另一个智能体在下次同步时就会获取到。

---

## 费用

| 组件 | 每月费用 |
|-----------|-------------|
| Render Pro（最低可行配置） | 约 $85 |
| Supabase（小型） | 免费到 $25 |
| OpenAI API（嵌入） | $5 到 $20（使用 ZeroEntropy 作为默认则更少） |
| Anthropic API（Claude） | $50 到 $500（取决于使用量） |
| **最低总计** | **约 $100 到 $150 每月** |

我的生产设置约为每月 $10,000，但那是 10 个实例、200 个定时任务、实时处理邮件和 Slack 和日历、运行子智能体。不是你第一天需要的。

> "明年不会是每月 $10,000。会是每月 $1,000。再下一年，会是每月 $100，然后每个人都会有。"

---

## 常见问题

1. **安装过程中 Render 内存不足。** 升级到 Pro 套餐。
2. **GitHub PAT 看不到仓库。** 创建仓库后重新加载页面。确保细粒度 token 选择了正确的仓库。
3. **Telegram 机器人不响应。** 检查 AlphaClaw 中的机器人 token。确保 Render 实例确实在运行。
4. **大量摄取时 Supabase 成为瓶颈。** 在小实例撑不住之前升级数据库实例大小。
5. **GBrain.io 配置失败。** 托管实例可能需要 Pro 套餐。检查 AlphaClaw UI 中的机器分配。

---

## 你构建了什么

你现在拥有一个运行在 Render 上的个人 AI 智能体，通过 Telegram 与你对话，拥有一个能摄取和记住你告诉它一切的大脑。每次对话都会被索引，每个新实体（人物、公司、交易、概念）都有自己的页面，夜间丰富守护进程在你睡觉时去重和整合。你醒来时拥有一个比你睡觉前更聪明的智能体。

下一步：

- **接入外部系统的摄取。** 邮件、日历、语音通话、推文、Slack。技能已经安装好了；你只需配置凭证。参见 [`docs/integrations/`](../integrations/) 获取各来源的配置方法。
- **连接你现有的 AI 客户端**（Claude Code、Cursor、Claude Desktop）到同一个大脑。参见 [`docs/mcp/`](../mcp/) 获取各客户端的设置方法。
- **正确设置梦想周期。** 自动驾驶守护进程默认运行夜间丰富，但你可以调整它做什么。参见 [`docs/architecture/`](../architecture/) 获取完整的周期参考。
- **为你的大脑添加队友**，或将其搭建为公司大脑。参见[公司大脑教程](company-brain.md)获取多人使用指南。

有问题、踩坑或值得分享的成功经验？在 [github.com/garrytan/gbrain](https://github.com/garrytan/gbrain/issues) 提交 issue。
