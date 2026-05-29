---
title: 'Claude Code 架构设计分析：基于官方文档与公开行为的工程推断'
description: '基于 Anthropic 官方 Claude Code 文档、公开产品行为和 OpenAI Agent 文档，对 Claude Code 的产品形态、权限模型、工具系统、Hooks、上下文管理与自研 Agent 启发做克制分析。'
pubDate: 2026-04-02
tags: ['AI技术', '架构设计']
---

# Claude Code 架构设计分析：基于官方文档与公开行为的工程推断

这篇文章不再把 Claude Code 写成对内部实现的确定性拆解。截至 2026-05-29，我能可靠依赖的是 Anthropic 官方文档、OpenAI 官方文档、公开 CLI 行为，以及少量可复现的使用经验。凡是官方文档没有明确说明的内部实现，本文都只作为架构推断或设计启发，不作为事实断言。

Claude Code 的价值不在于“终端里多了一个聊天窗口”，而在于它把自然语言、代码库上下文、工具调用、权限控制、会话恢复和外部集成组合成一个面向软件工程任务的 Agent 产品。它看起来像 CLI，但真正值得分析的是背后的产品边界：什么时候让模型行动，什么时候要求人审批，什么时候把能力交给外部工具，什么时候通过配置和 Hook 把组织策略前置。

---

## 事实边界

本文只把下列内容当作相对确定的事实：

- Claude Code 是 Anthropic 官方定位的“agentic coding tool”，运行在终端中，可以编辑文件、运行命令、创建提交，并可通过 MCP 连接外部工具和数据源。参见 [Claude Code overview](https://docs.anthropic.com/en/docs/claude-code/overview)。
- Claude Code 支持全局、项目、本地和企业策略等多层设置；权限配置包含 `allow`、`ask`、`deny`、`additionalDirectories`、`defaultMode` 等字段。参见 [Claude Code settings](https://docs.anthropic.com/en/docs/claude-code/settings)。
- Claude Code 的安全文档明确强调默认只读、对文件编辑和命令执行等动作请求许可，以及用户可以选择一次性批准或自动允许。参见 [Security](https://docs.anthropic.com/en/docs/claude-code/security)。
- Claude Code Hooks 是官方公开的扩展点，文档列出了 `PreToolUse`、`PostToolUse`、`Notification`、`UserPromptSubmit`、`Stop`、`SubagentStop`、`PreCompact`、`SessionStart`、`SessionEnd` 等事件，并说明输入、输出、退出码和 JSON 返回方式。参见 [Hooks reference](https://docs.anthropic.com/en/docs/claude-code/hooks)。
- Claude Code 支持自定义 slash commands、subagents、MCP、memory、SDK、OpenTelemetry 等能力。参见 [Slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands)、[Subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)、[MCP](https://docs.anthropic.com/en/docs/claude-code/mcp)、[Memory](https://docs.anthropic.com/en/docs/claude-code/memory)、[Claude Code SDK](https://docs.anthropic.com/en/docs/claude-code/sdk)、[Monitoring](https://docs.anthropic.com/zh-CN/docs/claude-code/monitoring-usage)。
- OpenAI 的公开 Agent 文档也采用“模型 + 工具 + 控制流 + 评估/追踪”的产品框架，可作为自研 Agent 的横向参照，但不能反推 Claude Code 的内部实现。参见 [OpenAI Agents](https://platform.openai.com/docs/guides/agents)、[Agents SDK](https://platform.openai.com/docs/guides/agents-sdk/)、[Responses API](https://platform.openai.com/docs/guides/migrate-to-responses)、[Using tools](https://platform.openai.com/docs/guides/tools?api-mode=responses)。

以下内容本文不再直接断言：

- 不断言 Claude Code 的 Hook 总数是某个固定数字。官方 Hooks 文档会随版本变化，本文只讨论文档中可见的事件类别。
- 不断言某个内部版本号带来了某项架构变更，除非能在官方 release notes 或文档中找到明确来源。
- 不断言启动时间、内存占用、token 节省比例、缓存命中收益等性能数字。
- 不断言存在 “Agent Teams”“ToolSearch”“Task 工具族”“官方插件数量”等内部或实验能力，除非官方文档有清晰命名和说明。
- 不把任何插件、社区示例或本地观察写成 Anthropic 官方架构。

---

## Claude Code 的核心产品形态

Claude Code 的官方描述可以概括为三件事：它在终端中工作，它可以采取行动，它可以通过 MCP 与外部系统连接。这三个点决定了它不是传统 IDE 插件的同类替代，而更接近一个“受权限约束的工程 Agent 外壳”。

传统补全工具的主路径通常是：

```text
人编辑代码 -> 模型补全/建议 -> 人接受或拒绝
```

Claude Code 的主路径更像：

```text
人描述目标 -> 模型理解任务 -> 选择工具 -> 请求必要权限 -> 执行 -> 回传结果 -> 继续或结束
```

这个差异很重要。前者的执行单位是“下一段代码”，后者的执行单位是“一个工程任务中的下一步行动”。因此，Claude Code 的关键设计不是补全质量本身，而是 Agent 行动链路是否可控：

| 维度 | 传统补全/聊天式工具 | Claude Code 暴露出的产品形态 |
| --- | --- | --- |
| 交互入口 | 编辑器内补全、侧边栏聊天 | 终端 REPL、CLI、脚本化调用 |
| 主要动作 | 生成代码片段或解释 | 读文件、改文件、运行命令、创建 PR/提交等工作流 |
| 权限边界 | 多由 IDE 或宿主插件决定 | settings、权限规则、用户确认、Hook、企业策略共同约束 |
| 上下文来源 | 当前文件、打开的文件、检索结果 | 项目文件、CLAUDE.md、命令上下文、MCP 资源、会话历史 |
| 扩展方式 | 插件 API 或 IDE 扩展 | Slash commands、subagents、MCP、Hooks、SDK |

这里的“Agent”不应被理解为神秘的自治系统。更工程化的理解是：模型在一个循环中持续接收上下文，选择工具，把工具结果重新纳入上下文，再决定下一步。Claude Code 的产品工作，是把这个循环放在一个可审计、可恢复、可配置的开发者环境里。

---

## 权限与工具：行动能力的边界

Claude Code 的工具能力越强，权限设计越关键。官方安全文档强调默认只读，编辑文件、运行测试、执行命令等动作需要显式许可。这说明 Claude Code 的安全核心不是“模型足够聪明所以可以信任”，而是“模型提出行动，人或策略决定是否放行”。

从公开文档可以推断出一个保守的权限链路：

```text
模型提出工具调用
    |
    v
命中 Hooks 的工具前置事件（如 PreToolUse）
    |
    v
匹配 settings / 企业策略中的 allow、ask、deny 规则
    |
    v
必要时请求用户确认
    |
    v
执行工具并把结果回传给模型
```

这只是架构推断，不代表 Anthropic 内部实现顺序完全如此。可确认的是：

- settings 支持多层级配置和权限规则；
- Hooks 可以在工具使用前后运行，并可通过退出码或 JSON 输出影响行为；
- 安全文档把用户许可和组织策略放在重要位置；
- MCP 工具也会进入权限和连接管理的范围。

对自研 Agent 来说，关键启发不是复制 Claude Code 的配置字段，而是把权限系统设计成一等模块：

- 工具需要声明副作用级别，例如只读、写文件、执行命令、访问网络、调用外部 SaaS。
- 权限规则应该能按工具名、参数范围、目录、命令前缀和外部服务 scope 做约束。
- 默认策略应保守，尤其是 shell、文件写入、网络请求和凭证相关能力。
- 允许组织策略覆盖个人偏好，避免“本地方便”绕过团队安全要求。
- 对每一次高风险动作保留可审计记录，包括谁批准、批准了什么参数、工具返回了什么摘要。

---

## Hooks：把 Agent 生命周期暴露成工程接口

Hooks 是 Claude Code 最值得借鉴的设计之一。它把 Agent 工作流中的关键时刻暴露为外部命令，允许团队把确定性检查、日志、审计、上下文注入和质量门禁接进去。

官方 Hooks 文档列出的事件覆盖了几类时机：

| 类别 | 代表事件 | 架构意义 |
| --- | --- | --- |
| 会话 | `SessionStart`、`SessionEnd` | 初始化项目上下文、收集会话统计、做清理 |
| 用户输入 | `UserPromptSubmit` | 在模型处理前做输入校验或补充上下文 |
| 工具调用 | `PreToolUse`、`PostToolUse` | 对读写、命令、网络、MCP 等动作做前置和后置处理 |
| 上下文压缩 | `PreCompact` | 在压缩前保存关键约束或工作状态 |
| 停止 | `Stop`、`SubagentStop` | 在主 Agent 或子 Agent 尝试结束时做完成度检查 |
| 通知 | `Notification` | 把等待审批、空闲等状态接入外部通知系统 |

需要弱化的是：Hook 事件数量不应被写成固定架构事实。官方文档可能增加、调整或废弃事件。更稳妥的说法是，Claude Code 已经公开了覆盖“会话、输入、工具、压缩、停止、通知”等阶段的 Hook 机制。

Hooks 的工程价值在于“把概率系统接上确定性系统”。例如：

- `PreToolUse` 可以在写文件前运行静态检查脚本，阻止修改敏感路径。
- `PostToolUse` 可以在编辑后触发格式化、lint 或审计日志。
- `UserPromptSubmit` 可以阻止不符合组织规范的请求，或补充 issue、分支、环境信息。
- `Stop` 可以做轻量完成检查，但不应被神化为可靠的“自我改进循环”。如果要做迭代，应设置上限、记录状态，并避免无限消耗。

对自研 Agent 的启发是：不要把所有控制都塞进 prompt。prompt 适合表达策略和偏好，Hook 更适合表达可执行、可测试、可审计的组织规则。

---

## 上下文管理：不是把所有东西塞进窗口

Claude Code 官方 memory 文档把记忆分为企业、项目、用户等层级，项目和用户常见入口是 `CLAUDE.md`。Slash commands 文档还说明命令可以通过 `@` 引用文件，MCP 文档说明可引用 MCP resources。Subagents 文档说明子代理有独立上下文窗口。

这些公开能力反映出一个清晰方向：上下文不是一个大字符串，而是一组分层资源。

```text
基础指令
  + 用户/项目/企业记忆
  + 当前会话历史
  + 被引用文件
  + 工具结果摘要
  + MCP 资源
  + 子代理返回的结论
  + 必要时的压缩摘要
```

这里要避免两个事实风险：

- 不断言 Claude Code 内部有固定的“三层 Skill 加载”“某个字符预算”“某个 token 阈值”。
- 不断言压缩算法如何保留或删除消息，除非官方文档明确说明。

可以确定的是，Claude Code 支持 `/compact`、`--resume`、`--continue` 等会话连续性能力，也支持 memory 和文件引用。这些能力共同说明：长任务需要在“保留足够上下文”和“控制上下文膨胀”之间做工程权衡。

自研 Agent 可以从这里抽象出几条设计原则：

- 把长期规则写入稳定文件或配置，而不是依赖对话历史。
- 把临时任务状态和长期项目规范分开管理。
- 对大型工具输出做摘要和可追溯链接，不要无脑注入全文。
- 让用户能显式引用文件、目录、资源，而不是完全依赖模型自己搜索。
- 支持恢复会话，但不要假设恢复后拥有完整历史；要能重建关键工作状态。

---

## MCP 与外部工具：开放集成而非内置一切

MCP 是 Claude Code 扩展外部能力的主要公开路径。官方 MCP 文档说明 Claude Code 可以连接本地 stdio server、HTTP/SSE server，支持 local、project、user 等配置 scope，远程服务器可使用 OAuth，并且 MCP servers 可以暴露 tools、resources 和 prompts。

这带来两个架构意义：

第一，Claude Code 不需要把 Jira、Sentry、Figma、数据库、文档系统等能力全部内置。它只需要提供一个可管理的外部工具协议，把具体能力交给 MCP server。

第二，MCP 让“工具能力”和“上下文资源”统一进入 Agent 工作流。外部系统既可以作为工具被调用，也可以作为资源被引用，还可以提供 slash command 形式的 prompt。

需要谨慎的是，不能把“可连接很多 MCP server”写成“拥有无限工具生态”。MCP server 的质量、权限、认证、输出大小、速率限制、审计能力都不同。官方文档也提到 MCP 输出可能产生大量 token，并提供输出 token 限制相关配置。

对自研 Agent 的启发：

- 外部工具协议比内置工具列表更重要。
- 每个外部工具都要带权限、认证、输出限制和错误恢复策略。
- MCP 或类似协议接入后，工具描述本身也会占用上下文，需要做选择性暴露和分页。
- 对高风险外部动作，如删 issue、发邮件、部署、转账，必须有人类确认或组织策略放行。

---

## Subagents：专业化上下文，而不是“多 Agent 神话”

Claude Code 的 subagents 官方文档说得比较克制：它们是可配置的专用 AI 助手，有自己的系统 prompt、工具权限和独立上下文窗口；Claude Code 可以根据任务描述和 subagent description 主动委托，也可以由用户显式调用。

这已经足够构成一个实用设计：把复杂任务拆给专门角色处理，同时避免主会话上下文被细节淹没。

```text
主会话
  |
  +-- code-reviewer subagent：关注质量、安全、可维护性
  |
  +-- test-runner subagent：关注测试失败和修复路径
  |
  +-- debugger subagent：关注错误复现和根因定位
```

但不应进一步断言：

- 子代理一定并行执行；
- 子代理之间一定完全隔离到进程级；
- 存在官方 “Teammate”“Agent Teams” 调度系统；
- 有固定的任务生命周期工具族或后台监控指标。

这些都可能是特定版本、实验功能、社区插件或其他产品形态的观察，不适合作为公开文章里的确定架构事实。

自研 Agent 使用 subagent 思路时，应优先解决三个工程问题：

- 委托边界：什么任务值得委托，什么任务应该主 Agent 自己完成。
- 返回格式：子代理输出必须结构化，否则主 Agent 很难综合。
- 工具权限：子代理不应默认继承所有高风险工具。

---

## 可观测性：Agent 需要被评估，而不是只看最终回答

Claude Code 的监控文档说明它支持 OpenTelemetry 指标和事件，且遥测需要显式配置；敏感信息默认不应进入指标或事件。OpenAI 的 Agent 文档也把 traces、evals、trace grading 放在优化 Agent 的关键位置。

这说明 Agent 产品的成熟度不能只看“能不能完成任务”，还要看过程是否可观察：

- 工具调用了多少次；
- 哪些工具最常失败；
- 哪些权限请求被拒绝；
- 哪类任务最容易超时或消耗过高；
- 用户在哪些步骤频繁接管；
- 修改代码后是否通过测试；
- 失败 trace 是否能用于回归评估。

对自研 Agent 来说，观测系统应从第一天设计进去。否则团队只能看最终输出，很难判断问题来自模型、工具、上下文、权限、网络、prompt 还是用户目标不清。

---

## 值得借鉴的设计

**1. 把 CLI 当成 Agent 的执行环境。** 终端天然连接文件系统、版本控制、测试、构建、部署和脚本。Claude Code 选择终端作为主场，使它更接近真实工程操作链路。

**2. 权限不是弹窗，而是一套策略系统。** `allow`、`ask`、`deny`、企业策略、用户确认和 Hooks 共同构成边界。自研 Agent 如果只有“允许/不允许”开关，很快会在可用性和安全性之间失衡。

**3. Hooks 让组织规则可编程。** 模型可以理解语义，但组织安全、合规、发布流程更适合用确定性脚本表达。Hooks 是把两者连接起来的接口。

**4. MCP 降低了外部集成的边际成本。** 一个 Agent 产品不可能内置所有 SaaS 和内部系统。协议化的工具接入，才可能形成可维护生态。

**5. Memory 和 commands 把隐性工作流显性化。** 团队规范、常用命令、PR 流程、测试要求不应反复靠人提醒，应该进入项目级记忆或命令文件。

**6. Subagents 的重点是上下文隔离。** 多 Agent 并不天然更强。它真正有用的地方，是让专门任务在独立上下文里处理，再把结论压缩回主流程。

---

## 不能直接断言的部分

为了降低事实风险，以下说法不适合作为公开结论：

- “Claude Code 有 19 个标准 Hook 事件。”更稳妥的写法是：官方 Hooks 文档列出了多个覆盖会话、工具、压缩、停止和通知阶段的事件，具体清单应以文档为准。
- “某版本修复了 12 倍 token 成本、启动快 30ms、内存少 80MB。”除非引用官方 release notes，否则不写具体数字。
- “ToolSearch 在 MCP 工具超过 10% 上下文时自动启用。”如果没有官方文档，应改为：大型工具集合会带来工具描述占用上下文的问题，自研系统需要考虑按需暴露工具。
- “Agent Teams、Teammate、Task 工具族是 Claude Code 的正式架构层。”如果没有官方文档，应删除或标为未证实观察。
- “官方插件有 11+ 个并展示某些固定模式。”除非链接到官方插件清单，否则不要写数量。
- “从内部实现可知……”除非实现公开且链接到具体文件与版本，否则不要使用这个表述。

---

## 与自研 Agent 的启发

如果把 Claude Code 当成自研 Agent 的参考对象，我会抽象出下面这套最小架构：

```text
用户目标
  |
  v
Agent 编排层
  |
  +-- 上下文管理：项目规则、用户偏好、文件引用、会话摘要
  |
  +-- 工具注册表：文件、Shell、搜索、Web、MCP、内部 API
  |
  +-- 权限系统：allow / ask / deny、目录约束、命令约束、组织策略
  |
  +-- Hook 系统：输入前、工具前、工具后、停止前、会话结束
  |
  +-- 观测系统：trace、工具结果、成本、失败原因、人工接管点
  |
  v
执行与恢复：持久化 transcript、可恢复状态、测试与验证结果
```

这里最容易被低估的是权限和恢复。很多 Agent demo 可以在无权限约束的沙箱里跑通，但一旦进入真实代码库，就会遇到凭证、私有数据、破坏性命令、长任务中断、上下文膨胀、外部系统失败等问题。Claude Code 的公开设计给出的答案是：把这些问题产品化，而不是只靠模型“自觉”。

OpenAI 的 AgentKit、Agents SDK、Responses API 文档也指向类似趋势：现代 Agent 平台不只是模型调用接口，而是围绕工具、控制流、状态、追踪、评估和部署形成完整工程框架。Claude Code 则展示了这个框架在软件工程终端场景中的一种产品形态。

---

## 写在最后

Claude Code 值得研究，但不适合被神化。它公开展示出的架构方向很清楚：让模型进入真实工程环境，同时用权限、Hooks、上下文管理、MCP 和可观测性限制风险、扩大能力。

更准确的结论是：Claude Code 不是“内部藏着某套神秘 Agent OS”，而是一个把 Agent 循环工程化的开发者产品。它的启发不在某个未经证实的内部机制，而在这些朴素但关键的设计取舍：默认保守、工具可控、上下文分层、外部能力协议化、过程可观察、人类仍然保留关键审批权。

---

## 参考来源

- Anthropic: [Claude Code overview](https://docs.anthropic.com/en/docs/claude-code/overview)
- Anthropic: [Set up Claude Code](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- Anthropic: [Claude Code settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- Anthropic: [Security](https://docs.anthropic.com/en/docs/claude-code/security)
- Anthropic: [Hooks reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- Anthropic: [Slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- Anthropic: [Subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- Anthropic: [Connect Claude Code to tools via MCP](https://docs.anthropic.com/en/docs/claude-code/mcp)
- Anthropic: [Manage Claude's memory](https://docs.anthropic.com/en/docs/claude-code/memory)
- Anthropic: [Claude Code SDK](https://docs.anthropic.com/en/docs/claude-code/sdk)
- Anthropic: [Monitoring](https://docs.anthropic.com/zh-CN/docs/claude-code/monitoring-usage)
- OpenAI: [Agents](https://platform.openai.com/docs/guides/agents)
- OpenAI: [Agents SDK](https://platform.openai.com/docs/guides/agents-sdk/)
- OpenAI: [Migrate to the Responses API](https://platform.openai.com/docs/guides/migrate-to-responses)
- OpenAI: [Using tools](https://platform.openai.com/docs/guides/tools?api-mode=responses)
