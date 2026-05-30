# 教程：将个人大脑扩展为公司大脑

本教程从[个人大脑教程](personal-brain.md)结束的地方继续。你已经有一个运行中的智能体（Render 上的 OpenClaw，通过 Telegram 与你对话，GBrain 作为记忆，Supabase 存储嵌入）。现在你希望整个团队将其用作共享的制度记忆，每个人只能看到他们被允许看到的内容。

**时间：** 在个人大脑安装基础上再约 90 分钟。
**费用：** 25 人公司每月持续花费低于 $100。

如果你还没有完成个人大脑安装，请[先从那里开始](personal-brain.md)。当你的智能体能在 Telegram 上回复你时再回来。本教程假设那已经正常工作了。

我是 Garry Tan。我构建了 GBrain 来运行我在 Y Combinator 的 AI 智能体。经过几个月的多用户功能开发（跨团队来源的并行同步、每用户 OAuth 作用域、每条读取路径的无泄漏隔离），它终于可以作为公司大脑使用了。如果今天要为一家 10-50 人的公司搭建，这就是我会运行的方案。

---

## 第一部分：心智模型

### 从个人到公司，什么变了

你构建的个人大脑是单用户系统：一个 git 仓库、一个智能体、你的内容。公司大脑是相同的架构加上三个新增功能：

1. **多个来源**在同一个大脑内。你的会议笔记是一个来源。每个队友的客户笔记本是另一个来源。共享的公司 wiki 是第三个来源。它们存在于同一个数据库中但保持独立。
2. **按用户登录**带作用域。每个队友获得自己的 OAuth 凭证。该凭证决定他们可以读写哪些来源。Alice 写入她的客户来源，读取她的加上共享来源。Bob 写入内部运营，读取他的加上共享来源。两人都看不到对方的写入。
3. **每人文件夹、定时任务和技能。** 共享大脑有共享结构，但每个队友拥有自己的子文件夹用于自己的工作、自己的计划任务（每周摘要、客户跟进）和自己的作用域技能。

### 这不是什么

它**不是**不同的安装。个人大脑中的智能体运行时、Supabase 后端、GBrain CLI 和 AlphaClaw 框架保持你设置的样貌不变。我们是在那个技术栈上添加，不是替换。

它也**不是**到处都是瘦客户端的设置。你的个人智能体保持原样（OpenClaw + Telegram）。每个队友添加自己选择的客户端（Claude Code、Cursor、Claude Desktop、自己的 OpenClaw 等）并指向大脑。

### 你获得了个人大脑没有的东西

- **共享记忆。** 整个团队查询同一个大脑。Alice 在周二写的合同笔记在周五 Bob 查询那个客户时会显示出来，并带有引用回 Alice 笔记的链接。
- **作用域隐私。** 绩效评审不会泄漏到客户查询中。法律文件不会泄漏到销售搜索中。我们在每条读取路径上做了模糊测试，零泄漏。
- **一个同步管道。** 你的大脑 git 仓库（如果需要按团队隔离则用多个）为大脑提供数据。每个人都能看到最新内容。
- **一个运维负担。** 一台服务器需要监控，而不是每人一台。

---

## 第二部分：将大脑后端切换为多用户 Postgres

个人大脑安装使用 Supabase 作为嵌入层，但 GBrain 运行时本身可能使用的是 PGLite（单机），取决于你选择的路径。对于公司大脑，运行时也需要一个真正的 Postgres。如果你的个人大脑安装已经端到端使用 Postgres 或 Supabase，跳到第三部分。

如果你在 PGLite 上，迁移：

```bash
gbrain migrate --to supabase
```

这会将每个页面、块、嵌入、链接和配置复制到你的 Supabase 项目。从智能体主机上运行，和个人大脑教程中设置的同一台。每 10K 页面大约需要几分钟。

验证：

```bash
gbrain doctor
gbrain stats
```

页面数量和块数量应该与你在 PGLite 上的一致。

---

## 第三部分：将大脑切分为多个来源

个人大脑有一个来源（名为 `default`）存放所有内容。对于公司大脑我们需要多个。正确的划分取决于你的组织。以下是 10-50 人公司的典型起始配置：

```bash
# 所有人都能读的共享来源
gbrain sources add shared --path /srv/brain-repos/shared --name "Shared company wiki"

# 销售/客户笔记的作用域来源
gbrain sources add customers --path /srv/brain-repos/customers --name "Customer notes"

# 仅内部文档（法务、HR、绩效、董事会）的作用域来源
gbrain sources add internal --path /srv/brain-repos/internal --name "Internal-only"
```

每个 `--path` 是你检出了 git 仓库的磁盘目录。创建它们：

```bash
sudo mkdir -p /srv/brain-repos
sudo chown $USER /srv/brain-repos
cd /srv/brain-repos
git clone git@github.com:your-org/shared-wiki.git shared
git clone git@github.com:your-org/customers.git customers
git clone git@github.com:your-org/internal-docs.git internal
```

你也可以保留现有的个人大脑仓库作为来源之一。只需选择它扮演的角色（如果已经是组织范围的内容，可能是 `shared`）。

### 两种作用域模型（选择适合你的）

有两种方式来限定队友的访问权限。适合不同的部署形态。

**模型 A：独立来源 + OAuth 作用域（推荐用于真正的多用户、不同 AI 客户端场景）。** 本教程引导你完成的方案。每个队友获得自己的 OAuth 客户端，携带 `--source` + `--federated-read` 标志。大脑在 SQL 层拒绝跨来源读取；隔离由数据库强制执行。每个队友可以运行自己的 MCP 感知客户端（Claude Code、Cursor、自己的 OpenClaw 等），作用域始终有效。

**模型 B：一个来源、基于目录的每人作用域（更简单，适合一个智能体服务所有人的设置）。** 我在生产中实际运行的形态：一个名为 `default` 的来源，内部有 `partners/<slug>/` 约定（如 `partners/alice-example/`、`partners/bob-example/`）。每个合伙人有自己的子目录存放个人页面：`partners/alice-example/USER.md`、`partners/alice-example/concepts/`、`partners/alice-example/sources/` 等。没有 OAuth 强制隔离；智能体本身执行 "Alice 的写入到她的 partners/ 子目录" 规则。当你只有一个智能体通过 Telegram 或单一共享接口服务所有人时，这是正确的模型。运维更简单，不需要每用户 OAuth，但作用域仅靠约定。

对于大多数公司大脑安装（10+ 队友，每人有自己的 AI 客户端），模型 A 是正确的起点。如果你运行的是个人大脑教程中的胖智能体服务所有人的模式，模型 B 确实更简单。你也可以混合使用：为明显不同的内容（客户笔记 vs 仅内部）使用独立来源，同时在共享来源内部使用 `partners/<slug>/` 约定作为每人工作区。

### 每个来源内的每人文件夹结构

在每个来源内，给每个队友自己的子文件夹。这是我运行的结构：

```
customers/
├── alice-example/                      ← Alice 的客户笔记本
│   ├── customers/
│   │   ├── acme-co.md
│   │   └── widget-systems.md
│   └── meetings/
│       └── 2026-05-21-acme-renewal.md
├── bob-example/                        ← Bob 的客户笔记本
│   └── customers/
│       └── orbit-bio.md
└── shared-customers/                   ← 两人都能看到的内容
    └── all-active-deals.md
```

这个结构给你两个好处：

1. **每个队友的写入到自己的文件夹**，即使它们在同一个来源中。不会意外覆盖。
2. **你以后可以将某人的文件夹拆分为独立来源**（如果 Alice 离职，新人接手她的客户，你可以将 `alice-example/` 移到以新人命名的新来源并相应调整作用域）。

`internal/` 也是相同的结构：`internal/alice-example/` 存放她的 HR 文档，`internal/bob-example/` 存放他的，`internal/legal/` 存放所有人都能读的法律文档等。

现在同步所有内容：

```bash
gbrain sync --all
```

每个来源在各自的锁下并行同步，不会互相干扰。输出如下：

```
[shared]    100/100 pages
[customers] 240/240 pages
[internal]   85/85 pages
✓ all sources synced
```

检查仪表盘：

```bash
gbrain sources status
```

你应该看到所有三个来源都有最近的同步时间戳和页面数量。

---

## 第四部分：通过 HTTP MCP 和 OAuth 暴露大脑

个人大脑通过 AlphaClaw 框架经 Telegram 与你对话。对于公司大脑，我们需要一个每个队友的 AI 客户端都能独立访问的路径。HTTP MCP 服务器就是这个路径。

```bash
gbrain serve --http --port 3131 --bind 0.0.0.0
```

`--bind 0.0.0.0` 很重要。默认情况下服务器仅绑定到 localhost，这对个人安装是正确的，但会阻止远程队友。设置 `0.0.0.0` 接受来自任何接口的连接。

服务器首次启动时会将管理员引导 token 打印到 stderr。保存它。你将用它登录一次管理仪表盘。

开发环境，通过 ngrok 隧道将本地服务器暴露出去：

```bash
ngrok http 3131 --domain your-brain.ngrok.app
```

生产环境，将你的服务器放在真实域名和真实 TLS 证书后面。我们用 `https://brain.acme-co.com` 作为本教程剩余部分的最终 URL。

使用公共 URL 重新运行服务器，使 OAuth 发现元数据与客户端访问的内容匹配：

```bash
gbrain serve --http --port 3131 --bind 0.0.0.0 --public-url https://brain.acme-co.com
```

你应该能访问 `https://brain.acme-co.com/health` 并获得 `{"status":"ok"}` 响应。

---

## 第五部分：为每个队友注册一个 OAuth 客户端

每个队友（或为队友服务的 AI 智能体）获得自己的 OAuth 客户端。客户端控制他们可以写入和读取的内容。

```bash
# Alice（销售）：写入 customers/alice-example，读取 customers + shared
gbrain auth register-client alice-example \
  --grant-types client_credentials \
  --scopes read,write \
  --source customers \
  --federated-read customers,shared

# Bob（运营）：写入 internal/bob-example，读取 internal + shared
gbrain auth register-client bob-example \
  --grant-types client_credentials \
  --scopes read,write \
  --source internal \
  --federated-read internal,shared

# Carol（法务）：写入 shared/legal，读取全部三个
gbrain auth register-client carol-example \
  --grant-types client_credentials \
  --scopes read,write \
  --source shared \
  --federated-read shared,customers,internal
```

每条 `register-client` 命令会打印 `client_id` 和 `client_secret`。为每个队友保存这两个值。它们用于队友的本地智能体配置。

关于标志的说明：

- `--scopes read,write` 允许客户端查询大脑和写入新页面。对于只读客户端（高管摘要、仪表盘），可以省略 `write`。`admin` 作用域用于运行命令如 `gbrain remote doctor`，通常保留给你自己的管理员客户端。
- `--source` 控制写入权限。一个客户端只能写入一个来源。在该来源内，第三部分的文件夹约定确保每个人的写入在自己的子文件夹中。
- `--federated-read` 控制读取范围。一个客户端可以从一个或多个来源读取。

### 验证作用域确实生效

在将大脑交给队友之前，验证隔离。在你的本地机器上使用各客户端的凭证打开两个终端窗口：

```bash
# 终端 1，以 Alice 身份
export GBRAIN_REMOTE_CLIENT_ID=<Alice 的 client_id>
export GBRAIN_REMOTE_CLIENT_SECRET=<Alice 的 client_secret>
export GBRAIN_REMOTE_MCP_URL=https://brain.acme-co.com/mcp

gbrain search "performance review" --remote
```

Alice 应该只看到 `customers` 和 `shared` 的结果。绩效评审笔记在 `internal` 中，她没有权限读取。她不应该看到它们。

```bash
# 终端 2，以 Bob 身份（类似地导出他的凭证）
gbrain search "performance review" --remote
```

Bob 应该看到 `internal` 中的绩效评审笔记，加上 `shared` 中的相关内容。他不应该看到只存在于 `customers` 中的任何内容。

如果两个查询都返回了正确作用域的结果，隔离就在正常工作。

---

## 第六部分：设置每人定时任务

个人大脑安装每晚为一名用户运行一次梦想周期（夜间丰富）。公司大脑需要每人定时任务，因为每个队友有自己的上下文：Alice 想要早上 7 点的客户管道摘要，Bob 想要早上 9 点的运营状态报告，Carol 想要每周一的合同合规检查。

每个定时任务只是一个使用队友客户端凭证的定时 `gbrain agent run` 调用。计划存放在工作区仓库（个人大脑教程中 AlphaClaw 部署的那个）的 `crons/` 目录中。典型布局：

```
your-org/myagent/
└── crons/
    ├── alice-example/
    │   └── 07am-customer-digest.md
    ├── bob-example/
    │   └── 09am-ops-status.md
    └── carol-example/
        └── monday-contract-compliance.md
```

每个定时任务文件声明其计划和智能体运行的提示：

```markdown
---
schedule: "0 7 * * *"
client: alice-example
---

# 客户管道摘要

提取 customers/alice-example/ 中过去 7 天有活动的每个客户页面。
对每个客户，总结发生了什么变化以及下一步行动是什么。
输出为 markdown 摘要，发布到 Slack #alice-customers，
保存副本到 customers/alice-example/digests/YYYY-MM-DD-pipeline.md。
```

`client:` 字段告诉定时任务运行器使用哪个 OAuth 客户端，从而强制作用域。Alice 的定时任务只能读取 Alice 的来源和写入 Alice 的文件夹。它不会意外触碰到 Bob 的客户笔记。

要安装定时任务计划，将文件提交到工作区仓库，让 AlphaClaw 在下次部署时拾取。定时任务调度技能（GBrain 安装的 60 个技能之一）负责调度。

---

## 第七部分：添加每人技能

GBrain 安装的 60+ 技能是通用的。你的团队可能需要一些特定的技能。示例：

- `onboarding-new-hire`。只有 Carol（HR）运行这个。引导生成欢迎包、安排入门会议、开通账号。
- `customer-success-followup`。只有 Alice（销售）运行这个。拉取最新客户页面，起草跟进邮件，发布到她的审核队列。
- `weekly-team-digest`。只有你（管理员）运行这个。将每个人发布的页面汇总为一份周报。

技能只是工作区仓库 `skills/` 目录中的 markdown 文件。结构如下：

```
your-org/myagent/
└── skills/
    ├── onboarding-new-hire/
    │   └── SKILL.md
    ├── customer-success-followup/
    │   └── SKILL.md
    └── weekly-team-digest/
        └── SKILL.md
```

每个 `SKILL.md` 声明触发条件（智能体监听的英文动词）和流程。使用 `gbrain skillify scaffold <name>` 命令生成模板：

```bash
gbrain skillify scaffold onboarding-new-hire
```

这会创建目录 + SKILL.md + 路由条目。编辑 SKILL.md 描述流程，提交，部署。智能体在下次请求时拾取新技能。

技能的每人作用域在路由层处理：技能可以在 frontmatter 中声明 `allowed_clients: [carol-example]`。如果 Alice 要求她的智能体运行该技能，智能体会拒绝并提示"此技能作用域限定为 carol-example。"

### skills 根目录下的共享规则文件

在各个技能目录旁，在 `skills/` 根目录下放置一些 `_*-rules.md` 文件。这些是每个技能都会读取的约定。我在生产中运行的：

- `_brain-filing-rules.md`。"这个新页面属于哪里？"的铁律决策树。编号的首次匹配获胜规则（人物放在 `people/`，公司在 `companies/`，会议在 `meetings/` 等）。每个摄取技能在创建页面之前都会查阅它。
- `_output-rules.md`。输出质量标准（确定性链接从 API 数据构建而非 LLM 组合的字符串、引用的精确措辞要求、禁止 AI 模板化用语）。
- `_excluded-people.md`。隐私门控。即使出现在源材料中也绝不能在大脑中被引用或归属的姓名。重新归属或丢弃。这是防止你的智能体意外发布你认定不适合公开的人物信息的文件。
- `_operating-rules.md`。操作约定（何时写入大脑 vs 暂存区、何时要求确认、何时发送通知）。
- `_x-ingestion-rules.md`、`_x-api-rules.md`。特定集成的每来源规则（如 Twitter）。

这些文件成为智能体实际执行的公司政策。编辑一个文件，所有读取它的技能在下次请求时就会采用新规则。通过 git 版本控制，可在 PR 中审查。

---

## 第八部分：谨慎接入 Slack

Slack 是大多数团队首先想要的集成，它有足够多的坑值得单独讲解。我运行的约定：

**两个定时任务，两种工作。** 一个扫描定时任务每 5-15 分钟运行一次，发现信号（你关注的频道中的新话题、队友被提及、决策）。一个归档定时任务每晚运行，存储完整对话历史。这样拆分意味着紧急信号得到快速处理，而慢速归档工作不会挤占实时频道。

**频道到任务 ID 的映射。** 不要让你的智能体用实际的频道 ID（`C03A8...`）引用 Slack 频道。构建一个 `topic-registry.json`（或类似文件），将每个频道 ID 映射为友好的任务名称（`acme-co-customer-success`、`engineering-standup`）。定时任务和技能通过友好名称引用频道；注册表在运行时翻译为 ID。当频道被重命名或替换时，你只需编辑这个文件。

**仅使用确定性链接。** 当你的智能体写入引用 Slack 消息的大脑页面时，链接必须从 API 数据（工作区 ID + 频道 ID + 消息时间戳）构建，绝不能由 LLM 组合。LLM 经常编造 Slack URL。这个约定放在 `_output-rules.md` 中；每个涉及 Slack 的技能都继承它。

**已忽略项状态。** 扫描定时任务记住它已经呈现过的内容。如果某个频道在周二有一个话题被判定为噪音，已忽略项文件会记录它，这样周三的扫描就不会再次呈现。没有这个机制，重新扫描会变成重复信号的洪流。

**每频道作用域镜像每人作用域。** 敏感频道（#executive、#legal、#performance）应该限定给具有相应 `--federated-read` 的队友。大脑存储所有内容，但谁能查询通过第五部分中的相同 OAuth 客户端模型来门控。

生产中实现这些的实际技能名为 `slack`、`slack-scan`、`slack-archive`。用 `gbrain skillify scaffold slack-scan` 在你的工作区中创建等效技能，然后编辑生成的 SKILL.md 声明你的频道映射和触发条件。

---

## 第九部分：亲自引导每个队友（botmaster 模式）

这部分决定了你的公司大脑是真正被采用还是闲置不用。

**不要只是把 OAuth 凭证交给新队友让他们"试试看"。** 他们会发一个查询，得到一个还没有个性化的结果（因为他们的数据分区是空的），然后认为它没用，再也不回来了。

有效的做法是：我亲自引导每个新队友。流程如下。

### 第 1 步：预填充他们的数据分区

在他们登录之前，我预填充他们的 `partners/<their-slug>/` 目录（或他们的专属来源），放入让他们觉得大脑已经了解他们的上下文：

- `partners/alice-example/USER.md`。一页个人简介：角色、关注领域、当前前 3 个优先事项、他们倾向于问什么类型的问题、他们偏好的写作风格（简洁 vs 详细、随意 vs 正式）。
- `partners/alice-example/concepts/`。5-10 个专属于他们的框架或反复出现的主题。如果 Alice 做销售，那就是"管道阶段定义"、"ICP 标准"、"异议处理手册"。
- `partners/alice-example/sources/`。他们关心的文档链接（他们团队的共享文档、他们的收件箱约定、他们查看的仪表盘）。
- 2-3 个示例大脑条目，展示数据形态：一个他们会认出的客户页面、一个他们参加过的最近会议的笔记、一个他们与团队分享的想法。

每个队友大约花 20 分钟。回报：当他们运行第一个查询的那一刻，大脑用他们的上下文回答，而不是一个通用回复。这就是"这是个酷工具"和"它了解我"之间的区别。

### 第 2 步：引导他们体验 2-3 个令人惊叹的流程

在让他们自由私信智能体之前，我亲自引导他们体验 2-3 个我知道会令人印象深刻的特定流程：

1. 展示综合能力的查询："向大脑询问[他们很了解的一个客户]。注意它是如何从三个来源中拉取页面，整合成一个带引用的答案。"这展示了大脑层的作用。
2. 展示缺口分析的查询："向大脑询问[它还不知道的事情]。注意它是如何告诉你缺少什么，而不是编造答案。"这建立了信任。
3. 写回流程："告诉大脑[他们刚开的一个会议]。注意它是如何自动归档、链接到在场的其他人，并呈现相关历史记录。"这展示了智能体作为记录工具（而不仅仅是查询工具）的价值。

这三个流程总共大约 15 分钟。到结束时，队友已经看到大脑做了他们自己不可能在那个时间内完成的事情。他们感到强大了。

### 第 3 步：只有令人惊叹之后才升级到私信

引导结束后，我给他们 OAuth 凭证和智能体的私信（Telegram、Slack 私信、你的任何接口）。我明确说"现在你可以问它任何问题，随时向它写入，它会不断从你那里学习。"

顺序很重要。如果你先给他们私信访问权限，期望他们自己发现令人惊叹的时刻，大多数不会。他们会发一个通用查询，得到一个通用答案，然后离开。Botmaster 模式（预填充 → 引导体验 → 升级到私信）翻转了转化率。

对每个新队友重复这个流程。每人总共约 45 分钟。与一个未被采用的内部工具的成本相比，这是你能花的最好的 45 分钟。

---

## 第十部分：连接每个队友的 AI 客户端

每个队友运行他们的 AI 客户端（Claude Code、Cursor、Claude Desktop、OpenClaw、Hermes 等），通过他们的 OAuth 凭证配置指向你的大脑服务器。

每个队友的推荐路径：瘦客户端安装。在他们的机器上：

```bash
curl -fsSL https://bun.sh/install | bash
bun install -g github:garrytan/gbrain

gbrain init --mcp-only \
  --issuer-url https://brain.acme-co.com \
  --mcp-url https://brain.acme-co.com/mcp \
  --oauth-client-id <他们的 client_id> \
  --oauth-client-secret <他们的 client_secret>
```

瘦客户端安装创建一个知道如何与你的大脑对话的本地配置，但永远不会打开自己的数据库。大多数 CLI 命令透明地通过远程服务器路由。

然后他们配置 AI 客户端。对于 Claude Desktop，队友在 `~/Library/Application Support/Claude/claude_desktop_config.json` 中添加一个 MCP 服务器条目：

```jsonc
{
  "mcpServers": {
    "company-brain": {
      "command": "gbrain",
      "args": ["serve"]
    }
  }
}
```

Claude Desktop 启动时，它通过本地 `gbrain serve` stdio 桥接通信，该桥接将每个请求通过 HTTPS 附带他们的 OAuth token 转发到你的远程大脑。从 Claude Desktop 的角度看，它就是一个 MCP 服务器。

对于 Claude Code、Cursor、OpenClaw、Hermes 和其他客户端，各客户端的设置步骤在 [`docs/mcp/`](../mcp/) 中。它们都遵循相同的模式：将智能体指向本地 `gbrain serve` 桥接，该桥接知道远程服务器。

---

## 第十一部分：队友的第一次真实查询

让 Alice 从她的机器上运行一个真实查询。有趣的动词是 `gbrain think`，它返回综合答案而不是原始页面。

```bash
gbrain think "acme-co 的最新动态是什么？我们上次什么时候和他们谈的？"
```

假设大脑已经同步了一周，她的来源包含 acme-co 的客户页面和几份会议笔记，Alice 会得到：

```
## 答案

与 acme-co 最近的客户联系是一次续约讨论会议，时间是 2026-05-18，
参会人员有 alice-example 和 acme-co 的 CTO。讨论要点
[customers/alice-example/meetings/2026-05-18-acme-renewal]：

- 他们正在从团队版升级到企业版。
- 年度合同价值从 $48K 提升到 $180K。
- 决策驱动因素：他们需要在 Q3 之前满足一项新的合规要求。

之前的联系是 2026-04-03 的季度检查
[customers/alice-example/meetings/2026-04-03-acme-q2-checkin]。

**缺口提示：** 自 2026-05-18 续约会议以来没有提交过客户成功笔记。
如果已经发生了后续跟进，大脑中还没有记录。
```

注意三点：

1. **有来源。** 每个声明都引用了它来源的会议笔记。
2. **已综合。** Alice 没有阅读三页内容然后拼接在一起。大脑做到了。
3. **对缺口诚实。** 大脑知道它不知道什么并如实告知，而不是编造一个没发生过的后续跟进。

最后一部分是缺口分析。这是大脑层中其他产品都不具备的功能。

Bob 问同样的问题不会得到任何关于 acme-co 的信息。他没有权限读取 `customers`。如果问与他相关的内容，他会看到自己的内部运营内容。Carol 问则会看到两者，因为她有权限读取所有三个来源。

---

## 第十二部分：运维公司大脑

三条命令完成大部分运维工作。

### 后台守护进程：`gbrain autopilot`

个人大脑安装已经开启了这个。对于公司大脑，同一个自动驾驶覆盖所有你的来源，因为它们在一个数据库中。它每五分钟运行一次；健康大脑（健康分数 95+）会休眠；漂移的大脑会提交定向维护任务。

### 自愈：`gbrain doctor --remediate`

```bash
gbrain doctor --remediate --yes --target-score 90 --max-usd 5
```

计算一个依赖排序的维护任务计划，将大脑健康分数提升到 `--target-score`，运行计划，拒绝超过 `--max-usd` 上限的花费。可安全地放在定时任务中。

### 监控：`gbrain sources status` 和管理仪表盘

```bash
gbrain sources status
```

返回每来源仪表盘：每个来源上次同步时间、页面数、已嵌入数、未确认的同步失败数。一目了然的健康检查。

`https://brain.acme-co.com/admin` 的管理仪表盘显示实时请求量、已注册的 OAuth 客户端、最近活动和大脑统计信息。使用第四部分的管理员引导 token 首次登录，然后从仪表盘内注册其他管理员用户。

---

## 第十三部分：费用和速度预期

来自公开发布的基准测试的实际数字，运行默认技术栈（GBrain 使用 ZeroEntropy 进行嵌入 + 重排序）：

- **嵌入费用：** 每百万 token $0.05。对比之下，GBrain 配置 OpenAI 为 $0.13（贵 2.6 倍），Voyage 为 $0.18（贵 3.6 倍）。
- **摄取速度：** 164 页的小测试语料库在主机上约 22 秒。对于 10K 页的语料库，首次约 20 分钟，之后大多数同步是增量的，几秒内完成。
- **查询延迟：** `gbrain search` 中位数约 122 ms。对比之下，通过 GBrain 使用 OpenAI 的相同查询约 282 ms。
- **综合答案延迟：** 几秒，主要由 Anthropic API 决定。
- **检索质量：** 在公开的 LongMemEval 基准上，GBrain 在前 5 个检索会话中达到 97.60% 的召回率，超过了之前发表的 96.6% 的最佳水平。在内部 BrainBench 关系查询语料上，GBrain 比普通向量检索高出 38 个百分点，因为图层发现了单纯向量相似性遗漏的关系。

完整方法和每次运行的收据 JSON 在 [gbrain-evals 仓库](https://github.com/garrytan/gbrain-evals/blob/main/docs/benchmarks/2026-05-23-v0.40.6.0-snapshot.md) 中。

对于 25 人的公司持续使用，预计嵌入每月约 $35（ZeroEntropy $0.05/百万 token），Anthropic 综合答案查询调用每月约 $50，加上你的托管费用。对于你这个规模的大多数公司，AI 方面每月不超过 $100。

---

## 第十四部分：常见坑

### "我的队友什么都看不到"

在主机上检查 `gbrain auth list`，确认他们的客户端 `--source` 设置为实际存在的来源。空或 null 的 `--source` 意味着客户端回退到 `default` 来源，如果你设置了三个命名来源，它可能没有内容。

### "同步很慢，感觉卡住了"

首次同步需要嵌入每个页面，这需要时间。检查 `gbrain sources status` 查看实时页面数量。如果在增长，你没有卡住，只是在嵌入。如果你有 10K 页的语料库且 ZeroEntropy 被限流，每来源并行同步看起来像是三个来源同时有进展，而不是一个来源快速推进。

### "我看到了不该看到的页面"

这不应该发生，但如果你怀疑有问题，以受限客户端身份运行 `gbrain search <查询> --remote --json`，检查每个返回结果的 `source_id` 字段。每一行都应该在客户端的 `--federated-read` 集合中。如果有不在的，提交 issue 并附上准确的 slug 和来源 ID。

### "综合答案有误"

大脑层基于检索到的页面生成答案。如果检索到的页面包含错误信息，答案也会出错。缺口分析提示通常会捕获这个问题：如果答案说"基于日期 X 的检索页面"而日期 X 是六个月前，大脑在告诉你信息过时了。运行 `gbrain sync --all` 刷新后重试。

### "OAuth `/token` 端点为我的客户端返回 401"

验证客户端密钥是否与 register-client 时打印的一致。服务器只存储 SHA-256 哈希；如果你丢了原始密钥，必须撤销客户端并重新注册。使用 `gbrain auth revoke-client <client_id>` 然后重新运行 `register-client`。

### "Postgres 连接耗尽"

每个并行同步工作者打开自己的连接池。三个来源加上默认每个来源四个工作者，如果 Postgres 连接限制设置得低，可能会达到上限。使用 `gbrain sync --all --parallel 2 --workers 2` 减少工作者数量，或将 Postgres `max_connections` 提高到至少 100。Supabase 免费层默认为 60，比较紧张。

### "我想添加第四个队友，但他们需要访问所有三个来源"

```bash
gbrain auth register-client diana-example \
  --grant-types client_credentials \
  --scopes read,write \
  --source shared \
  --federated-read shared,customers,internal
```

就这样。随着组织发展添加或轮换队友。

---

## 你构建了什么

你现在拥有了前一个教程中的个人大脑智能体，加上一个多用户共享层：三个联邦来源分别存放共享、客户和仅内部内容；每个来源内的每人文件夹确保队友的写入不会冲突；每人 OAuth 客户端带作用域的读写权限；每人定时任务按各自的时间表和作用域运行；每人技能只在正确的用户触发时运行。每个队友通过 AI 客户端用自然语言查询大脑，获得经过正确作用域限定的、有来源的综合答案。

下一步：

- **接入外部系统的摄取**（Granola、Linear、Slack），使用[摄取来源契约](../skillpack-anatomy.md)。大多数公司希望会议自动摄取，这样大脑无需任何人手动输入笔记就能保持最新。
- **通过管理 UI 设置团队专属仪表盘。** 每个团队负责人可以有自己的大脑健康和活动视图。
- **探索大脑层的其他功能。** `gbrain whoknows`（找到某个话题的专家）、`gbrain find_trajectory`（某个指标随时间如何变化）、`gbrain founder scorecard`（对 VC 和运营团队特别有用）、检测不同人笔记之间矛盾的矛盾检测周期。

如果你在这个领域构建（YC 已将其标记为 [Request for Startups 中的公司大脑类别](https://www.ycombinator.com/rfs#company-brain)），不妨在此基础上构建。上面描述的一切都是开源的，MIT 许可，是我在自己的 AI 智能体背后运行的生产方案。

有问题、踩坑或值得分享的成功经验？在 [github.com/garrytan/gbrain](https://github.com/garrytan/gbrain/issues) 提交 issue。
