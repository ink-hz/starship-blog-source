---
title: 'Claude Code 架构设计深度拆解：AI编程Agent的操作系统级设计'
description: '基于源码的深度拆解：Agent循环引擎、四层插件化能力模型、五层纵深安全防御、九大事件钩子、MCP开放生态、上下文分层管理。不是给IDE加个聊天窗口，是重新定义人和代码的交互方式。'
pubDate: 2026-04-02
tags: ['AI技术', '架构设计']
---

# Claude Code 架构设计深度拆解：AI编程Agent的操作系统级设计

> 大多数AI编程工具的架构是"IDE + 聊天窗口"。Claude Code的架构是"Agent操作系统 + 工具生态"。这不是程度差异，是范式差异。

---

## 一、AI编程助手的本质：从补全到自主

打开任何一个AI编程工具——Copilot、Cursor、Codeium——你看到的都是同一个范式：

```
人写代码 → AI 补全/建议 → 人确认 → 人继续写
```

这个范式有一个隐含假设：**人是编程的主体，AI是辅助工具。** 人决定写什么、改什么、在哪里改，AI只在人的操作间隙提供建议。

但这个假设正在崩塌：

- 开发者可能说"把这个模块的认证方式从Session换成JWT"——这涉及十几个文件的联动修改，不是任何单点补全能覆盖的
- 开发者可能说"这个bug的根因是什么？修掉它"——这需要读代码、搜索、推理、定位、修复的完整链路
- 开发者可能说"参考这个API文档，给我写一套完整的集成"——这跨越了理解文档、设计接口、编写代码、补充测试的多个阶段

**这些真实的开发意图，单点补全永远覆盖不了。**

AI编程补全的本质是对开发者下一步操作的预测——猜对了，效率翻倍；猜错了，开发者按Tab之前还得检查一遍。而随着任务复杂度增长，猜对的概率越来越低。

---

## 二、范式跳跃：从补全到Agent循环

Claude Code的核心设计决策不是"做一个更好的补全工具"，而是**把AI从辅助者变成执行者**。

```
旧范式：人写代码 → AI 补全 → 人确认 → 人继续
        人是操作者，AI是建议器，能力边界由IDE功能决定

新范式：人表达意图 → Agent 理解意图 → Agent 自主规划 → 调用工具执行 → 结果反馈 → 继续或退出
        Agent是操作者，人是审批者
        没有预设的操作流程——开发者的意图不可预测，不需要预设路径
```

这不是"给终端加个AI"。这是一次代际跃迁——**从工具变成了自主系统。**

### 核心范式对比

| 维度 | 传统AI编程工具 | Claude Code |
|------|--------------|-------------|
| **交互入口** | IDE内嵌补全、侧边栏 | 终端原生，自然语言（唯一入口） |
| **用户角色** | 操作者（人写代码，AI建议） | 审批者（Agent执行，人确认） |
| **能力边界** | 由IDE API和训练数据决定 | 由工具权限+LLM能力+插件生态决定 |
| **多步任务** | 人工串联每一步 | Agent自主编排完整链路 |
| **扩展方式** | 编写TypeScript/Python插件 | 编写Markdown描述 |
| **自迭代** | 无 | Stop钩子驱动反思-改进循环 |

---

## 三、Agent循环引擎——核心执行架构

### 3.1 Agent主循环的完整链路

Claude Code的Agent循环不是简单的"输入→输出"，而是一个**持续运转的决策引擎**。每次工具执行的结果重新进入LLM上下文，触发下一轮推理，形成闭环。

```
┌─────────────────────────────────────────────────────────────────┐
│                     Agent 主循环完整链路                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  用户输入（自然语言 / 斜杠命令）                                   │
│       │                                                         │
│       ▼                                                         │
│  ┌──────────────────┐                                          │
│  │ UserPromptSubmit  │  ← 钩子拦截点①                           │
│  │ Hook              │    输入验证、规则注入、上下文增强            │
│  └────────┬─────────┘                                          │
│           ▼                                                     │
│  ┌──────────────────┐                                          │
│  │ 命令/Agent触发决策 │  ← 检查斜杠命令匹配                       │
│  │                  │    检查Agent描述中的<example>模式匹配        │
│  │                  │    无匹配则进入标准Claude循环                │
│  └────────┬─────────┘                                          │
│           ▼                                                     │
│  ┌──────────────────────────────────────────────┐              │
│  │           LLM 推理层（决策引擎）                │              │
│  │                                              │              │
│  │  上下文理解 → 任务规划 → 工具选择 → 参数构造    │              │
│  │                                              │              │
│  │  输入：用户意图 + 项目上下文 + 历史对话         │              │
│  │       + CLAUDE.md规范 + 已激活Skill知识        │              │
│  │  输出：工具调用请求（tool_name + tool_input）   │              │
│  └────────┬─────────────────────────────────────┘              │
│           ▼                                                     │
│  ┌──────────────────┐                                          │
│  │  PreToolUse Hook  │  ← 钩子拦截点②                           │
│  │                  │    接收：{tool_name, tool_input}            │
│  │                  │    返回：allow / deny / ask / defer         │
│  │                  │    可修改：updatedInput                     │
│  └────────┬─────────┘                                          │
│      ┌────┴────┐                                               │
│      ▼         ▼                                               │
│   denied    allowed                                             │
│   跳过执行    │                                                  │
│      │        ▼                                                 │
│      │   ┌──────────────────┐                                  │
│      │   │  工具执行层       │                                  │
│      │   │                  │                                  │
│      │   │  Read / Write / Edit / Bash / Grep                  │
│      │   │  Glob / WebFetch / WebSearch                        │
│      │   │  Agent / Skill / MCP工具                             │
│      │   └────────┬─────────┘                                  │
│      │            ▼                                             │
│      │   ┌──────────────────┐                                  │
│      │   │ PostToolUse Hook  │  ← 钩子拦截点③                   │
│      │   │                  │    结果处理、日志记录、质量验证      │
│      └───┤                  │                                   │
│          └────────┬─────────┘                                  │
│                   ▼                                             │
│          执行结果回传 → 重新进入 LLM 推理层                       │
│                   │                                             │
│              ┌────┴────┐                                       │
│              ▼         ▼                                       │
│           未完成     已完成                                      │
│           继续循环     │                                        │
│                       ▼                                        │
│              ┌──────────────────┐                              │
│              │   Stop Hook      │  ← 钩子拦截点④               │
│              │                  │    检查完成标准                │
│              └────────┬─────────┘                              │
│                  ┌────┴────┐                                   │
│                  ▼         ▼                                   │
│              approve     block                                  │
│              允许退出     阻止退出                                │
│                 │         │                                     │
│                 ▼         ▼                                     │
│            会话结束    重新注入提示                                │
│                │      → 回到推理层（自迭代）                      │
│                ▼                                               │
│       ┌──────────────────┐                                     │
│       │  SessionEnd Hook  │  ← 钩子拦截点⑤                     │
│       │  状态保存、资源清理 │                                     │
│       └──────────────────┘                                     │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 消息处理管道

Agent循环中的每条消息都经过标准化的处理管道：

```
用户/工具输出
    ↓
消息序列化（JSON格式）
    {role: "user|assistant",
     content: [{type: "text", text: "..."},
               {type: "tool_use", id: "...", name: "...", input: {...}}]}
    ↓
上下文窗口检查
    ├─ 未超限 → 直接进入LLM推理
    └─ 接近限制 → 触发 PreCompact Hook → 自动紧凑
                    ├─ 移除非关键消息
                    ├─ 合并工具输出
                    ├─ 保留核心上下文（CLAUDE.md、Skill、钩子指令）
                    └─ 检测抖动循环（连续3次紧凑后停止并报错）
    ↓
会话转录持久化（JSONL格式）
    ~/.claude/ 目录
    ↓
LLM API调用
    ↓
响应解析 → 工具调用请求 或 文本回复
```

### 3.3 自迭代机制——Stop Hook驱动的反思循环

这是Claude Code最精巧的设计之一。Ralph Wiggum插件展示了完整的实现：

**状态文件**（`.claude/ralph-loop.local.md`）：
```
┌──────────────────────────────────┐
│  YAML Frontmatter                │
│  iteration: 3                    │  ← 当前迭代次数
│  max_iterations: 10              │  ← 最大迭代限制
│  completion_promise: "DONE"      │  ← 完成标记
├──────────────────────────────────┤
│  原始 Prompt 文本                 │  ← 每次迭代重新注入
└──────────────────────────────────┘
```

**Stop Hook 判定流程**：

```
Claude 尝试退出
    │
    ▼
读取 .claude/ralph-loop.local.md
    │
    ├─ 文件不存在 → exit 0（允许退出）
    │
    ├─ iteration >= max_iterations → exit 0（允许退出）
    │
    ├─ 检查最后一条Assistant消息中是否包含
    │   <promise>DONE</promise> → exit 0（允许退出）
    │
    └─ 未满足退出条件：
        递增 iteration 计数
        返回 {"decision": "block",
               "reason": "原始prompt文本",
               "systemMessage": "🔄 迭代 N/M"}
        → Claude 重新处理相同任务
        → 看到自己的历史工作（文件变更、git状态）
        → 自主改进和迭代
```

**本质：这不是简单的重试，而是"带记忆的自我改进"。** Claude看到自己上一轮的全部工作结果，基于此进行反思和优化。

### 3.4 多Agent并行调度

Feature-Dev插件展示了复杂的多Agent编排模式：

```
Phase 1: 需求理解
    │
    ▼
Phase 2: 代码库探索（3个Agent并行）
    ├─ code-explorer Agent 1 ──┐
    ├─ code-explorer Agent 2 ──┤── 并行执行，各自搜索不同方向
    └─ code-explorer Agent 3 ──┘
                                │
                                ▼
                          收集所有输出 → 综合分析
                                │
                                ▼
Phase 3: 方案设计（3个Agent并行）
    ├─ code-architect Agent 1 → 最小改动方案
    ├─ code-architect Agent 2 → 清洁架构方案
    └─ code-architect Agent 3 → 务实平衡方案
                                │
                                ▼
                          对比方案 → 推荐选择
                                │
                                ▼
Phase 4: 用户确认 → Phase 5: 实现 → Phase 6: 测试 → Phase 7: PR
```

**调度关键设计**：
- SubAgent之间互相独立，不共享上下文
- 主Agent看摘要和结论，SubAgent深入细节（上下文隔离）
- SubagentStop钩子可在子Agent完成时做质量检查
- 子Agent完成后释放状态，节省内存

---

## 四、四层插件化能力模型——能力解耦与自由组合

Claude Code的能力不是铁板一块，而是由四种正交组件自由组合。每种组件有独立的生命周期、触发机制和配置规范。

### 4.1 四层组件全景

```
┌──────────────────────────────────────────────────────────────┐
│                    插件（Plugin）                              │
│                                                              │
│  ┌─ Commands ─────────────────┐  ┌─ Agents ───────────────┐ │
│  │  用户触发的结构化工作流       │  │  自主完成任务的子代理     │ │
│  │                            │  │                         │ │
│  │  入口：/command-name        │  │  触发：自动匹配/显式调用  │ │
│  │  本质：写给Claude的指令      │  │  本质：独立的Agent循环    │ │
│  │  格式：Markdown + Frontmatter│  │  格式：Markdown + YAML  │ │
│  │                            │  │                         │ │
│  │  frontmatter字段：          │  │  frontmatter字段：       │ │
│  │  · description             │  │  · name（必需）          │ │
│  │  · allowed-tools           │  │  · description（必需）   │ │
│  │  · model                   │  │  · model（必需）         │ │
│  │  · argument-hint           │  │  · color（必需）         │ │
│  │  · disable-model-invocation│  │  · tools（可选）         │ │
│  └────────────────────────────┘  └─────────────────────────┘ │
│                                                              │
│  ┌─ Skills ───────────────────┐  ┌─ Hooks ────────────────┐ │
│  │  注入领域知识的上下文增强     │  │  拦截和扩展系统事件      │ │
│  │                            │  │                         │ │
│  │  触发：条件匹配自动加载      │  │  触发：事件驱动自动执行   │ │
│  │  本质：分层的知识注入        │  │  本质：AOP切面编程       │ │
│  │  结构：SKILL.md + refs/    │  │  格式：hooks.json        │ │
│  │                            │  │                         │ │
│  │  三级加载：                 │  │  两种执行模式：           │ │
│  │  · 元数据（~100字，始终）    │  │  · command（确定性）     │ │
│  │  · SKILL.md（<5k字，触发时） │  │  · prompt（LLM判断）    │ │
│  │  · references/（按需）      │  │                         │ │
│  └────────────────────────────┘  └─────────────────────────┘ │
│                                                              │
│  ┌─ MCP Servers ──────────────────────────────────────────┐  │
│  │  外部工具接入（.mcp.json）                               │  │
│  │                                                        │  │
│  │  四种传输协议：                                          │  │
│  │  · stdio  — 本地进程，JSON-RPC over stdin/stdout        │  │
│  │  · SSE    — 云端流式，Server-Sent Events，OAuth支持     │  │
│  │  · HTTP   — REST API，无状态请求/响应                    │  │
│  │  · WebSocket — 实时双向，持久连接                        │  │
│  │                                                        │  │
│  │  三种认证：OAuth自动处理 / Bearer Token / 环境变量注入    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 插件的完整生命周期

```
发现 (Discovery)
    │  扫描位置：
    │  · ~/.claude/plugins/（全局）
    │  · .claude-plugin/（项目）
    │  · npm全局安装
    │  必须存在：.claude-plugin/plugin.json
    ▼
加载 (Loading)
    │  1. 读取 plugin.json → 验证 name 字段
    │  2. 扫描默认目录：
    │     commands/*.md → 自动注册为斜杠命令
    │     agents/*.md → 自动注册为子Agent
    │     skills/*/SKILL.md → 自动注册元数据
    │     hooks/hooks.json → 加载事件处理器
    │     .mcp.json → 启动MCP服务器
    │  3. 合并自定义路径（补充默认，不替代）
    ▼
注册 (Registration)
    │  · 命令 → /command-name 可用
    │  · Agent → 自动匹配或@提及可用
    │  · Skills → 元数据进入触发池
    │  · Hooks → 绑定到事件系统
    │  · MCP → 服务器启动，工具列表获取
    ▼
运行 (Runtime)
    │  · Commands：用户 /command 时执行
    │  · Agents：Claude自动选择或用户手动触发
    │  · Skills：description匹配时SKILL.md加载到上下文
    │  · Hooks：对应事件触发时执行
    │  · MCP：Agent决定调用时请求MCP服务器
    ▼
卸载 (Unloading)
    · 命令不可用、Hooks解绑、MCP关闭、Skills卸载
    · 重启Claude Code时完全清理
```

**"约定优于配置"的设计原则**：把文件放到正确的目录，系统自动识别并注册。不需要中央注册表，不需要编写加载代码。插件开发的门槛降到了"会写Markdown"的程度。

### 4.3 Agent触发的决策机制

Agent不是随机触发的，而是基于description中的`<example>`块进行精确匹配：

```
Agent描述中定义的触发模式：
┌───────────────────────────────────────────────┐
│  <example>                                    │
│  Context: [场景描述]                            │
│  user: "[用户会说什么]"                          │
│  assistant: "[Claude如何响应并触发Agent]"        │
│  <commentary>[为什么应该触发]</commentary>       │
│  </example>                                    │
└───────────────────────────────────────────────┘

Claude评估流程：
    1. 解析所有已注册Agent的<example>块
    2. 匹配当前对话与例子的相似度
    3. 触发决策：
       ├─ 显式触发（用户明确请求："用code-reviewer看看"）
       ├─ 主动触发（基于工具使用模式匹配）
       └─ 隐式触发（用户暗示需求："这代码有bug吗"）
```

### 4.4 Skill的三级渐进式加载

Skill不是全部加载到上下文——这会浪费token并干扰推理。Claude Code设计了三级渐进式信息披露：

| 层级 | 内容 | 大小 | 何时加载 | 目的 |
|------|------|------|---------|------|
| **L1 元数据** | name + description | ~100字 | 始终加载 | Claude判断是否需要此Skill |
| **L2 核心知识** | SKILL.md正文 | <5000字 | Skill被触发时 | 提供工作所需的核心概念和流程 |
| **L3 深度资源** | references/目录 | 无限制 | Agent按需读取 | 详细文档、API参考、高级模式 |

**这解决了一个核心矛盾：知识量和上下文窗口的矛盾。** 全部加载会挤占宝贵的上下文空间，完全不加载则Agent缺乏领域知识。三级加载让Agent"先知道有什么，再按需深入"。

---

## 五、九大事件钩子——Agent生命周期的神经系统

钩子是Claude Code架构中最关键的扩展机制。它将Agent的完整生命周期抽象为9个标准事件，每个事件点都开放拦截和扩展。

### 5.1 事件全景与执行时序

```
┌─── 会话生命周期 ────────────────────────────────────────────┐
│                                                             │
│  SessionStart ──→ [项目检测、上下文预加载、环境变量设置]        │
│       │                                                     │
│       ▼                                                     │
│  UserPromptSubmit ──→ [输入验证、规则注入]                    │
│       │                                                     │
│       ▼                                                     │
│  ┌─── Agent循环 ──────────────────────────────────────┐    │
│  │                                                     │    │
│  │  PreToolUse ──→ [安全检查、权限验证、输入修改]        │    │
│  │       │                                             │    │
│  │       ▼                                             │    │
│  │  工具执行                                            │    │
│  │       │                                             │    │
│  │       ▼                                             │    │
│  │  PostToolUse ──→ [结果处理、日志记录、质量验证]       │    │
│  │       │                                             │    │
│  │       ▼                                             │    │
│  │  PreCompact ──→ [上下文压缩前保留关键信息]            │    │
│  │       │         （仅在接近窗口限制时触发）             │    │
│  │       ▼                                             │    │
│  │  SubagentStop ──→ [子Agent完成时质量检查]             │    │
│  │       │                                             │    │
│  │       ▼                                             │    │
│  │  Stop ──→ [退出检查、自迭代驱动]                      │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│       │                                                     │
│       ▼                                                     │
│  Notification ──→ [事件路由、外部告警]                       │
│       │                                                     │
│       ▼                                                     │
│  SessionEnd ──→ [状态保存、资源清理]                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 钩子配置的两种格式

**插件钩子**（`hooks/hooks.json`）——需要包装在 `hooks` 字段中：

```
{
  "description": "插件描述",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",           ← 工具名称匹配（正则）
        "hooks": [
          {
            "type": "prompt",              ← LLM智能判断
            "prompt": "验证文件写入安全性...",
            "timeout": 30
          },
          {
            "type": "command",             ← 确定性脚本检查
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

**用户钩子**（`.claude/settings.json`）——直接定义，无包装：

```
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {"type": "command", "command": "bash ~/my-validator.sh"}
      ]
    }
  ]
}
```

### 5.3 Matcher语法详解

| 语法 | 含义 | 示例 |
|------|------|------|
| 精确匹配 | 只匹配一个工具 | `"matcher": "Write"` |
| OR匹配 | 匹配任意一个 | `"matcher": "Write\|Edit\|Bash"` |
| 通配符 | 匹配所有工具 | `"matcher": "*"` |
| 正则模式 | 高级匹配 | `"matcher": "mcp__.*__delete.*"` |
| MCP工具 | 匹配特定MCP | `"matcher": "mcp__plugin_asana_.*"` |

### 5.4 两种钩子执行模式的设计权衡

| 维度 | 命令钩子（Command） | 提示钩子（Prompt） |
|------|-------------------|-------------------|
| **执行方式** | 运行Shell脚本/Python | 发送给LLM判断 |
| **速度** | 毫秒级 | 秒级（额外LLM调用） |
| **判断能力** | 正则匹配、文件检查 | 语义理解、上下文推理 |
| **确定性** | 100%确定 | 概率性判断 |
| **退出码语义** | 0=成功, 2=阻止, 其他=警告 | JSON返回决策 |
| **适用场景** | 明确规则（禁止rm -rf） | 模糊判断（代码是否有安全风险） |
| **支持事件** | 全部9个事件 | Stop/SubagentStop/UserPromptSubmit/PreToolUse |

**最佳实践：命令钩子做快速过滤，提示钩子做深度判断。两者互补，不互斥。**

### 5.5 钩子输入/输出数据格式

**钩子接收的输入**：
```
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",   ← 完整会话记录
  "cwd": "/current/working/dir",
  "permission_mode": "ask|allow",
  "hook_event_name": "PreToolUse",
  "tool_name": "Write",                            ← 当前工具名
  "tool_input": {"file_path": "...", "content": "..."}, ← 工具参数
  "tool_result": "..."                              ← PostToolUse时可用
}
```

**PreToolUse钩子返回**：
```
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",        ← 权限决策
    "updatedInput": {"file_path": "new_path"}      ← 可修改工具输入
  },
  "systemMessage": "安全警告：检测到敏感路径写入"
}
```

**Stop钩子返回**：
```
{
  "decision": "approve|block",
  "reason": "重新注入的prompt文本",                  ← block时必需
  "systemMessage": "🔄 迭代 3/10"
}
```

---

## 六、五层纵深安全模型——自主不等于失控

AI Agent执行代码操作的核心矛盾：**自主性越高，风险越大。** Claude Code的解法不是在"全开"和"全关"之间选一个，而是设计了五层递进的信任光谱。

### 6.1 五层防御全景

```
┌────────────────────────────────────────────────────────────────┐
│  Level 5: 企业策略层（最高优先级，不可被下层覆盖）                  │
│                                                                │
│  managed-settings.json                                         │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ disableBypassPermissionsMode: "disable"   ← 禁止绕过权限  │ │
│  │ allowManagedPermissionRulesOnly: true      ← 仅企业规则   │ │
│  │ allowManagedHooksOnly: true                ← 仅企业钩子   │ │
│  │ strictKnownMarketplaces: [...]            ← 锁定插件源   │ │
│  └──────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────┤
│  Level 4: 沙箱隔离层（进程级隔离，仅适用于Bash工具）               │
│                                                                │
│  sandbox配置                                                    │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ enabled: true                                             │ │
│  │ network:                                                  │ │
│  │   allowLocalBinding: false      ← 禁止本地端口绑定         │ │
│  │   allowAllUnixSockets: false    ← 禁止Unix Socket          │ │
│  │   allowedDomains: ["*.company.com"]  ← 域名白名单          │ │
│  │ autoAllowBashIfSandboxed: false ← 沙箱内Bash仍需确认      │ │
│  │ excludedCommands: []            ← 排除特定命令              │ │
│  └──────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────┤
│  Level 3: 工具权限层（细粒度的工具+参数模式匹配）                  │
│                                                                │
│  allowed-tools规则                                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ "Read"                          ← 所有读操作放行           │ │
│  │ "Bash(gh issue view:*)"         ← 只允许查看GitHub issue  │ │
│  │ "Bash(npm test:*)"              ← 只允许运行测试           │ │
│  │ "Write(src/**)"                 ← 只允许写src目录         │ │
│  │ "mcp__plugin_asana__*"          ← 允许Asana全部MCP工具    │ │
│  └──────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────┤
│  Level 2: 钩子拦截层（可编程的动态安全策略）                      │
│                                                                │
│  PreToolUse钩子                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ 命令钩子：正则匹配危险模式                                  │ │
│  │   · 检测 eval()、exec()、os.system()                      │ │
│  │   · 检测硬编码的 API_KEY、SECRET、TOKEN                    │ │
│  │   · 检测 innerHTML、dangerouslySetInnerHTML               │ │
│  │                                                          │ │
│  │ 提示钩子：LLM深度判断                                      │ │
│  │   · 语义级别的安全风险评估                                  │ │
│  │   · 上下文相关的权限决策                                    │ │
│  └──────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────┤
│  Level 1: 用户确认层（最后一道防线）                              │
│                                                                │
│  Ask模式                                                        │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ 敏感操作弹出确认框 → 人最终拍板                             │ │
│  │ 支持 allow / deny / defer 三种响应                         │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### 6.2 配置优先级（Settings Hierarchy）

从低到高，高层覆盖低层：

```
Claude Code 默认设置
    ↓ 覆盖
~/.claude/settings.json                ← 用户全局设置
    ↓ 覆盖
<project>/.claude/settings.json        ← 项目团队设置
    ↓ 覆盖
<project>/.claude/settings.local.json  ← 项目个人设置（不入库）
    ↓ 覆盖
managed-settings.json                  ← 企业管理覆盖（最高优先级）
```

### 6.3 安全钩子实战——security-guidance插件

security-guidance插件通过PreToolUse钩子监控所有Write/Edit操作，检测9种安全模式：

| 检测模式 | 匹配内容 | 风险等级 |
|---------|---------|---------|
| 命令注入 | `os.system()`, `child_process.exec()` | Critical |
| XSS | `innerHTML`, `dangerouslySetInnerHTML` | Critical |
| 代码执行 | `eval()`, `exec()`, `new Function()` | Critical |
| 反序列化 | `pickle.loads()` | High |
| GitHub Actions注入 | `${{ }}` in workflows | High |
| 硬编码凭证 | `API_KEY = "..."`, `SECRET = "..."` | High |
| SQL注入 | 字符串拼接SQL | Medium |
| 路径遍历 | `../` in file paths | Medium |
| 不安全HTTP | `http://` (非https) | Low |

### 6.4 权限评估级联——完整决策流程

当Agent发起一次工具调用时，权限系统的评估顺序是精确定义的。理解这个级联关系是理解安全模型的关键：

```
Agent发起工具调用（tool_name + tool_input）
    │
    ▼
Step 1: managed-settings检查（最高优先级）
    │
    ├─ managed deny列表命中 → 直接拒绝（不可覆盖）
    ├─ allowManagedPermissionRulesOnly=true
    │   → 只看managed规则，跳过用户规则
    └─ 未命中 → 继续
    │
    ▼
Step 2: PreToolUse Hook 评估（并行执行所有匹配Hook）
    │
    ├─ 任一Hook返回 "deny" → 拒绝
    │   └─ 触发 PermissionDenied Hook（可返回 {retry:true}）
    │
    ├─ 任一Hook返回 "ask" → 弹出用户确认
    │
    ├─ 任一Hook返回 "defer" → 暂停执行
    │   └─ headless模式下保存到磁盘
    │   └─ claude -p --resume 时重新评估
    │
    ├─ 所有Hook返回 "allow" → 跳过后续检查，直接执行
    │   ⚠️ 注意：Hook的allow可以绕过deny规则（设计选择）
    │
    └─ 无匹配Hook → 继续
    │
    ▼
Step 3: allowed-tools规则匹配
    │
    ├─ 命令级allowed-tools（Command frontmatter）
    │   └─ 匹配 → 允许
    │
    ├─ 会话级permissions（settings.json）
    │   ├─ allow列表命中 → 允许
    │   ├─ deny列表命中 → 拒绝
    │   └─ ask列表命中 → 弹出确认
    │
    └─ 未匹配任何规则 → 默认 ask（保守策略）
    │
    ▼
Step 4: 用户确认（Ask模式最终决策）
    │
    ├─ 用户允许 → 执行
    ├─ 用户允许并"总是允许此类操作" → 生成规则，后续自动放行
    └─ 用户拒绝 → 不执行
```

**关键设计细节**：
- **Hook的allow可以绕过deny规则**——这是有意的设计，允许插件在特定上下文中覆盖全局限制
- **"总是允许"生成的规则**在复合命令上可能产生无法匹配的规则（已知边界）
- **交互工具**（AskUserQuestion等）在allowed-tools中被隐式自动允许，不需要显式声明
- **managed-settings.d/**目录支持按字母顺序合并的策略分片，适用于大型组织的分层治理

### 6.5 Prompt Cache与安全的交互

Prompt Cache是性能优化的关键，但与安全模型有微妙的交互：

```
正常情况：
    系统提示（含安全规则）→ Cache命中 → 零额外token成本

异常情况（曾导致12倍token成本的bug）：
    工具Schema变更 / MCP服务器重连 / 自定义Agent加载
        → Cache失效
        → 整个系统提示重新发送
        → 单次调用token成本暴增12倍
```

**修复策略**：工具Schema变更时精确失效（只失效变更的部分），而非全量失效。这是"最小失效粒度"原则在缓存系统中的应用。

---

## 七、MCP协议——从封闭工具到开放生态的桥梁

### 7.1 MCP四种传输协议对比

| 特性 | stdio | SSE | HTTP | WebSocket |
|------|-------|-----|------|-----------|
| **传输方式** | 进程stdin/stdout | HTTP+SSE流 | REST请求/响应 | 双向连接 |
| **连接状态** | 有状态 | 有状态 | 无状态 | 有状态 |
| **认证方式** | 环境变量 | OAuth自动 | Headers | Headers |
| **最佳场景** | 本地工具/DB | 云端SaaS | 内部API | 实时监控 |
| **延迟** | 最低 | 中等 | 中等 | 低 |
| **进程管理** | Claude管理生命周期 | 外部服务 | 外部服务 | 外部服务 |

### 7.2 MCP工具命名规范

```
mcp__plugin_<插件名>_<服务器名>__<工具名>

示例：
mcp__plugin_asana_asana__asana_create_task
mcp__plugin_github_api__github_create_issue
```

### 7.3 环境变量展开

MCP配置中支持的变量：
- `${CLAUDE_PLUGIN_ROOT}` — 插件根目录（可移植性必须）
- `${CLAUDE_PROJECT_DIR}` — 当前项目目录
- `${CLAUDE_ENV_FILE}` — 会话环境变量文件（仅SessionStart可用）
- `${任意用户变量}` — 用户shell环境中的变量

---

## 八、上下文管理——Agent智能的基础设施

### 8.1 CLAUDE.md层级加载

```
~/.claude/CLAUDE.md                    → 全局偏好（个人级）
    ↓ 继承
项目根目录/CLAUDE.md                    → 项目规范（团队级）
    ↓ 覆盖
子目录/CLAUDE.md                        → 模块特殊规则
    ↓ 覆盖
.claude/settings.local.json            → 本地个人配置（不入库）
```

### 8.2 项目自动检测（SessionStart钩子）

```
会话开始
    │
    ├─ 检测 package.json     → PROJECT_TYPE=nodejs
    │   └─ 检测 tsconfig.json → USES_TYPESCRIPT=true
    ├─ 检测 Cargo.toml       → PROJECT_TYPE=rust
    ├─ 检测 go.mod           → PROJECT_TYPE=go
    ├─ 检测 pyproject.toml   → PROJECT_TYPE=python
    ├─ 检测 pom.xml          → PROJECT_TYPE=java, BUILD_SYSTEM=maven
    ├─ 检测 build.gradle     → PROJECT_TYPE=java, BUILD_SYSTEM=gradle
    │
    └─ 检测 .github/workflows → HAS_CI=true

环境变量通过 $CLAUDE_ENV_FILE 持久化，整个会话可用
```

### 8.3 上下文压缩的完整生命周期

压缩不是简单的"删掉旧消息"。它是一个有状态、有断路器、有副作用的复杂流程：

```
上下文token估算
    │
    ├─ < 80% 窗口 → 不触发，继续正常执行
    │
    ├─ 80%-98% → 预警，准备压缩
    │
    └─ ≥ 98% → 阻止新的工具调用，强制压缩
    │
    ▼
PreCompact Hook（钩子拦截点）
    │  允许插件在压缩前注入必须保留的信息
    ▼
压缩执行
    │
    ├─ 保留项（不可压缩）：
    │   · CLAUDE.md 文件内容
    │   · 已激活的 Skill 指令
    │   · 钩子规则和系统提示
    │   · 用户的明确约束和架构决策
    │   · 图像内容（保留以复用 Prompt Cache）
    │
    ├─ 压缩项：
    │   · 中间工具调用的完整输出 → 摘要
    │   · 重复读取的文件内容 → 去重
    │   · 搜索结果 → 保留关键匹配
    │   · 进度消息 → 剥离
    │
    ├─ 副作用处理：
    │   · 后台子Agent在压缩后变得不可见（需重新发现）
    │   · Plan Mode 可能在压缩后丢失（切回实现模式）
    │   · 脱延工具（ToolSearch）失去输入 Schema，需重新验证
    │
    ▼
PostCompact Hook（压缩完成后）
    │
    ▼
断路器检测
    │
    ├─ 压缩成功，上下文回到安全水位 → 继续
    │
    └─ 连续 3 次压缩后仍超限（抖动循环）
        → 停止并报可操作错误
        → 建议用户：开新会话 / 缩小任务范围 / 手动 /compact
           （防止无限烧费 API 调用）
```

**为什么断路器阈值是3次？** 这是一个工程权衡：1次太激进（可能是临时的大输出），5次太宽松（已经浪费了大量token）。3次在"给系统一次恢复机会"和"及时止损"之间取得平衡。

### 8.4 ToolSearch——脱延工具的自动管理

当MCP生态扩大后，所有工具的Schema描述可能占据大量上下文窗口。ToolSearch机制自动管理工具的"在场"和"缺席"：

```
MCP工具注册
    │
    ▼
上下文占比评估
    │
    ├─ 所有MCP工具描述 < 10% 上下文窗口
    │   → 全部常驻（正常模式）
    │
    └─ 所有MCP工具描述 ≥ 10% 上下文窗口
        → 自动启用 ToolSearch（脱延模式）
        │
        ▼
    ┌─────────────────────────────────┐
    │  ToolSearch 状态机               │
    │                                 │
    │  DORMANT（休眠）                 │
    │    │  Agent需要某工具时            │
    │    ▼                            │
    │  DISCOVERING（发现中）            │
    │    │  匹配工具描述                │
    │    ▼                            │
    │  LOADED（已加载）                │
    │    │  Schema注入到上下文           │
    │    ▼                            │
    │  RESOLVED（已调用）              │
    │    │  执行完毕                    │
    │    ▼                            │
    │  回到 DORMANT（释放Schema）       │
    └─────────────────────────────────┘
```

**关键限制**：
- 脱延工具输入超过 64KB 会导致挂起（需分片处理）
- 上下文压缩后脱延工具失去 Schema，需重新验证
- MCP工具描述上限 2KB（超出被截断）
- 冷启动竞态：工具可能在激活前就被脱延

**ToolSearch的本质是"按需加载"思想在工具层面的应用。** 类比操作系统的虚拟内存——不是所有页面都常驻物理内存，而是按需换入换出。

---

## 九、Task系统——后台Agent的并行执行引擎

这是Claude Code中一个完整的后台任务管理系统，本质是**在后台启动独立的Agent循环**，支持多Agent并行执行和协调。

### 9.1 Task生命周期

```
TaskCreate（创建任务）
    │
    │  参数：subject, description, activeForm, metadata
    │  返回：taskId
    │
    ▼
pending（等待中）
    │
    │  TaskUpdate(taskId, status: "in_progress")
    │
    ▼
in_progress（执行中）
    │
    │  后台Agent循环独立运行
    │  TaskOutput(taskId) 读取实时输出
    │  TaskStop(taskId) 可强制终止
    │
    ├─ 成功 → TaskUpdate(taskId, status: "completed")
    │
    └─ 异常 → 保持 in_progress，创建新Task描述blocker
    │
    ▼
completed / deleted
    │
    │  TaskList() 查看全局状态
    │  返回：token_count, tool_uses, duration_ms
```

### 9.2 Task工具族

| 工具 | 职责 | 关键参数 |
|------|------|---------|
| **TaskCreate** | 创建后台任务 | subject, description, activeForm |
| **TaskUpdate** | 更新状态/依赖 | status, addBlocks, addBlockedBy, owner |
| **TaskGet** | 读取任务详情 | taskId |
| **TaskList** | 列出所有任务 | — |
| **TaskOutput** | 读取后台输出 | taskId, block(是否阻塞等待), timeout |
| **TaskStop** | 终止运行中任务 | taskId |

### 9.3 任务依赖与编排

Task系统支持声明式的依赖关系：

```
TaskCreate("设计API接口")         → taskId: 1
TaskCreate("实现API接口")         → taskId: 2
TaskCreate("编写API测试")         → taskId: 3

TaskUpdate(taskId: 2, addBlockedBy: ["1"])    ← 2依赖1
TaskUpdate(taskId: 3, addBlockedBy: ["2"])    ← 3依赖2

结果：1 → 2 → 3 串行执行
```

**与Agent子循环的区别**：SubAgent在主循环内执行，共享会话上下文；Task在后台独立运行，有自己的Agent循环、token统计和超时管理。Task更适合**长时间运行、可并行、需要监控**的任务。

---

## 十、Memory系统——跨会话的持久化知识库

Memory不是上下文管理的一部分——它是**跨会话的长期记忆**，每次新会话自动加载，持续增量更新。

### 10.1 Memory架构

```
~/.claude/projects/<project-hash>/memory/
├── MEMORY.md                    ← 索引文件（指针，非内容）
├── user_role.md                 ← 用户信息记忆
├── feedback_testing.md          ← 行为反馈记忆
├── project_auth_rewrite.md      ← 项目记忆
└── reference_linear.md          ← 外部引用记忆
```

### 10.2 四种记忆类型

| 类型 | 存什么 | 何时存 | 怎么用 |
|------|-------|-------|-------|
| **user** | 用户角色、偏好、知识背景 | 学到用户信息时 | 定制回答方式和深度 |
| **feedback** | 用户对行为的纠正和确认 | 用户纠正或确认做法时 | 避免重复犯错，保持已验证的做法 |
| **project** | 在进的工作、截止日期、决策 | 学到项目状态时 | 理解任务背景和优先级 |
| **reference** | 外部系统的位置和用途 | 学到外部资源时 | 知道去哪里找信息 |

### 10.3 记忆文件格式

```markdown
---
name: 测试偏好
description: 用户要求集成测试使用真实数据库而非mock
type: feedback
---

集成测试必须连接真实数据库，不使用mock。

**Why:** 上季度mock测试通过但生产迁移失败，mock与真实行为有偏差。

**How to apply:** 写测试时默认使用测试数据库连接，除非用户明确要求mock。
```

### 10.4 加载与限制

```
SessionStart
    │
    ▼
自动加载 MEMORY.md 索引到上下文
    │
    ├─ 大小限制：25KB 截断
    ├─ 行数限制：200行截断
    └─ MEMORY.md只存指针，不存内容
    │
    ▼
Agent按需读取具体记忆文件
```

**MEMORY.md是索引，不是记忆本身。** 这个设计避免了所有记忆一次性挤占上下文窗口——Agent先看索引决定需要哪些记忆，再按需读取。

**什么不该存进Memory**：代码模式（读代码就行）、git历史（git log就行）、调试方案（修复在代码里）、CLAUDE.md已有的内容、临时性的任务状态。

---

## 十一、多层缓存策略——Token经济学的工程实现

Claude Code的每个设计决策都有token成本评估。缓存是控制成本的核心基础设施，分五层递进：

```
┌────────────────────────────────────────────────────────────┐
│  L5: 会话级缓存                                             │
│  · Remote session 24h持久化                                 │
│  · JSONL transcript 持久化到 ~/.claude/sessions/            │
│  · --resume 恢复时直接加载，不重新推理                        │
├────────────────────────────────────────────────────────────┤
│  L4: MCP缓存                                               │
│  · 工具列表缓存（服务器连接后一次性获取）                      │
│  · 服务器连接复用（避免重复握手）                              │
│  · ToolSearch延迟加载（不活跃的MCP工具不占token）              │
├────────────────────────────────────────────────────────────┤
│  L3: Skill缓存                                              │
│  · L1元数据常驻内存（~100字/skill）                           │
│  · L2 SKILL.md条件加载（触发时才进入上下文）                   │
│  · L3 references按需读取（Agent显式请求时）                   │
│  · description限制250字符                                    │
├────────────────────────────────────────────────────────────┤
│  L2: Prompt缓存                                             │
│  · 系统提示缓存（不变部分跨turn复用）                         │
│  · CLAUDE.md文件缓存（项目不变则缓存命中）                    │
│  · @-mention文件不JSON转义（减少序列化开销）                   │
├────────────────────────────────────────────────────────────┤
│  L1: 工具Schema缓存                                         │
│  · 工具定义JSON per-session缓存（避免每turn重新stringify）    │
│  · MCP工具schema在连接时一次性缓存                            │
│  · 动态工具变更时才invalidate                                │
└────────────────────────────────────────────────────────────┘
```

### Token节省的关键技术点

| 技术 | 节省方式 | 预估节省 |
|------|---------|---------|
| Skill三级加载 | 避免全部Skill内容挤占上下文 | 每Skill节省~5000 token |
| ToolSearch延迟加载 | 不活跃MCP工具不占token | 大型MCP生态下节省数万token |
| @-mention不转义 | 原始字符串替代JSON转义 | 大文件减少10-30% |
| Read compact行号 | 紧凑的行号格式 | 长文件减少5-10% |
| 工具schema缓存 | 避免每turn重新序列化 | 每turn节省~1000 token |
| 自动紧凑 | 压缩非关键消息 | 长会话可释放50%+上下文 |

---

## 十二、容错与恢复——Graceful Degradation设计哲学

Claude Code的容错策略不是Fail-Fast（快速失败），而是**Fail-Safe（安全降级）**——优先保持会话连续性，能恢复的绝不中断。

### 12.1 容错机制全景

```
┌─── 场景 ──────────────────── 策略 ──────────────────── 目标 ───┐
│                                                                 │
│  Image处理失败            → 自动剥离image blocks      → 不中断对话 │
│  Diff渲染超时             → 5秒后fallback到纯文本     → 不阻塞流程 │
│  Autocompact连续3次失败   → 停止并报可操作错误        → 不烧费API  │
│  MCP服务器断连            → 工具标记不可用+重试       → 不影响其他 │
│  Streaming idle 90s       → 可配timeout+graceful close → 不挂起   │
│  子进程环境泄露            → SCRUB=1清除云凭证        → 不泄密    │
│  SSH连接断开              → 会话持久化+resume恢复     → 不丢进度  │
│  大会话(>50MB)             → 消息自动删除+压缩       → 不OOM     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 12.2 会话恢复机制

```
正常会话
    │
    ├─ 中断（网络断开/终端关闭/SSH断连）
    │   └─ 会话状态已持久化到 ~/.claude/sessions/*.jsonl
    │       └─ claude --resume → 恢复完整上下文
    │
    ├─ 权限阻塞（headless模式下需要确认）
    │   └─ Deferred权限决策 → 工具调用处暂停
    │       └─ claude -p --resume → 重新评估权限并继续
    │
    └─ Compact失败（上下文溢出）
        └─ 检测抖动循环（3次紧凑后仍超限）
            └─ 停止并显示可操作错误（而非无限重试）
```

**关键原则：`--resume`是一等特性，不是事后补丁。** 所有设计都假设会话可能在任何时刻中断，因此每一步都保证可恢复。

---

## 十三、完整Hook事件清单——不止九个

文章前面介绍了9个核心Hook，但实际系统支持更多事件。完整清单：

| 事件 | 触发时机 | 支持的Hook类型 | 关键用途 |
|------|---------|---------------|---------|
| **SessionStart** | 会话初始化 | command | 项目检测、上下文预加载 |
| **SessionEnd** | 会话结束 | command | 状态保存、清理（1.5s超时，可配） |
| **UserPromptSubmit** | 用户输入后 | prompt/command | 输入验证、规则注入 |
| **PreToolUse** | 工具执行前 | prompt/command | 安全检查、权限验证、输入修改 |
| **PostToolUse** | 工具执行后 | prompt/command | 结果处理、日志记录 |
| **PreCompact** | 上下文压缩前 | command | 保留关键信息 |
| **Stop** | 主Agent尝试退出 | prompt/command | 完成检查、自迭代驱动 |
| **SubagentStop** | 子Agent完成 | prompt/command | 质量检查 |
| **Notification** | 系统通知 | command | 事件路由、外部告警 |
| **PermissionDenied** | 权限被自动拒绝 | command | 可返回`{retry: true}`让模型重试 |
| **CwdChanged** | 工作目录切换 | command | direnv集成、环境自动加载 |
| **FileChanged** | 文件变动 | command | 响应式工作流 |
| **TaskCreated** | 任务创建时 | command | 任务拦截和增强 |
| **TeammateIdle** | 团队Agent空闲 | command | 多Agent协作调度 |
| **TaskCompleted** | 任务完成时 | command | 清理、通知、后续触发 |

### Hook条件执行（if字段）

Hook不一定每次都执行。`if`字段支持条件匹配，减少不必要的进程开销：

```
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "if": "Bash(git *)",              ← 仅git命令时才执行此Hook
      "hooks": [
        {"type": "command", "command": "bash validate-git.sh"}
      ]
    }
  ]
}
```

### Hook输出大小控制

当Hook输出超过50KB时，系统不会将全部内容注入上下文（避免token浪费），而是保存到文件并在上下文中插入文件路径+预览摘要。

---

## 十四、工具系统深度设计——每个工具的职责边界

### 14.1 工具能力矩阵

| 工具 | 副作用 | 默认权限 | 特殊能力 |
|------|-------|---------|---------|
| **Read** | 无 | allow | PDF(限20页)、Jupyter、图片、行号范围 |
| **Write** | 创建/覆盖文件 | ask | 必须先Read才能Write已有文件 |
| **Edit** | 修改文件片段 | ask | 精确字符串替换、replace_all模式 |
| **Bash** | 执行任意命令 | ask | 沙箱隔离、超时控制、后台执行 |
| **Grep** | 无 | allow | ripgrep引擎、多行匹配、行号、head_limit |
| **Glob** | 无 | allow | 文件模式匹配、按修改时间排序 |
| **WebFetch** | 无 | ask | 15分钟缓存、HTML→Markdown、域名过滤 |
| **WebSearch** | 无 | ask | 域名白名单/黑名单 |
| **Agent** | 启动子Agent | allow | model覆盖、worktree隔离、后台执行 |
| **Skill** | 无 | allow | 加载Skill知识到上下文 |

### 14.2 Bash工具的沙箱细节

Bash是唯一支持沙箱隔离的工具，隔离维度：

```
┌─ 网络隔离 ────────────────────────────────────────┐
│  allowLocalBinding: false     ← 禁止监听本地端口   │
│  allowAllUnixSockets: false   ← 禁止Unix Socket    │
│  allowedDomains: [...]        ← 域名白名单          │
│  httpProxyPort / socksProxyPort ← 代理限制          │
├─ 进程隔离 ────────────────────────────────────────┤
│  excludedCommands: [...]      ← 排除特定危险命令    │
│  allowUnsandboxedCommands: false ← 禁止逃逸沙箱    │
│  CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 ← 清除子进程凭证│
├─ 行为限制 ────────────────────────────────────────┤
│  timeout: 120000ms（默认）     ← 2分钟超时          │
│  run_in_background: true      ← 支持后台执行        │
│  后台任务 ~45s无响应弹通知                           │
└───────────────────────────────────────────────────┘
```

**重要限制：沙箱仅适用于Bash。** Read、Write、WebFetch、MCP工具不经过沙箱。这意味着安全防线的完整性依赖于五层模型的协同，而非单靠沙箱。

---

## 十五、多模型策略——Effort参数与Extended Thinking

Claude Code不是只用一个模型，而是根据任务复杂度动态调整推理深度。

### 15.1 Effort三档推理

| Effort | 推理深度 | 适用场景 | Token消耗 |
|--------|---------|---------|----------|
| **low** | 快速回复，最少思考 | 简单问题、文件读取、格式化 | 最低 |
| **medium** | 平衡速度和质量 | 常规编码、代码审查 | 中等 |
| **high** | 深度思考，完整推理链 | 架构决策、复杂bug定位、安全分析 | 最高 |

### 15.2 Extended Thinking（自适应思考）

```
用户输入
    │
    ▼
模型能力检测
    ├─ 模型支持Extended Thinking → 自适应启用
    │   └─ 简单任务 → 自动跳过思考
    │   └─ 复杂任务 → 显示思考过程（thinking block）
    │
    └─ 模型不支持 → 标准推理
```

**`ultrathink`关键字**：在提示中包含此关键字，强制激活最深度的思考模式。适用于需要极致推理能力的场景（如复杂的并发bug、分布式一致性问题）。

### 15.3 多后端模型映射

Claude Code不绑定单一API，支持多个云后端：

| 后端 | 认证方式 | 特殊适配 |
|------|---------|---------|
| **Anthropic API** | API Key | 默认，全特性支持 |
| **AWS Bedrock** | SDK Profile | 冷启动优化、ARN映射 |
| **Google Vertex** | Service Account | Fine-grained streaming |
| **Microsoft Foundry** | API Token | 推理profile映射 |

`modelOverrides`配置允许将picker中的模型名映射到具体的后端模型标识符。

---

## 十六、Cron定时系统——会话级的后台调度

```
CronCreate
    │
    │  参数：cron表达式（5字段标准格式）、prompt、recurring标志
    │  示例："7 * * * *" → 每小时第7分钟执行
    │
    ▼
后台调度器
    │
    ├─ 仅在REPL空闲时触发（不中断正在进行的对话）
    ├─ recurring=true → 持续执行直到删除或3天自动过期
    ├─ recurring=false → 执行一次后自动删除（one-shot提醒）
    ├─ 内置jitter抖动 → 避免所有用户请求同时到达API
    │
    ▼
CronList / CronDelete → 查看和管理定时任务
```

**设计约束**：Cron任务仅存活于当前会话，不写入磁盘。会话结束即消失。这是有意的设计——避免用户忘记的定时任务在后台无限消耗资源。

---

## 十七、Worktree隔离——Git级别的工程隔离

```
主项目工作目录
    │
    │  EnterWorktree(name: "feature-x")
    │
    ▼
.claude/worktrees/feature-x/          ← 独立的git worktree
    │
    ├─ 独立的分支（基于HEAD创建）
    ├─ 独立的工作目录
    ├─ Agent在此目录中工作，不影响主项目
    ├─ 支持 sparse-checkout（大monorepo只检出必要目录）
    │
    │  ExitWorktree(action: "keep" | "remove")
    │
    ▼
keep → 保留worktree和分支，后续可恢复
remove → 清理worktree和分支（有未提交变更时需确认）
```

**Worktree + Agent的组合模式**：Agent工具支持`isolation: "worktree"`参数，让子Agent在独立的worktree中工作。这样主Agent的工作目录不受子Agent影响，多个子Agent可以并行修改不同分支。

---

## 十八、Remote Session与IDE集成

### 18.1 Remote Control

```
本地终端                           远程服务
    │                                │
    │  claude --remote               │
    │  ─────────────────────────────→│
    │                                │  Web UI渲染
    │  ←─────────────────────────────│  会话状态云端镜像
    │                                │  跨设备同步
    │  会话持久化到云端                │
    │  --resume 从任意设备恢复        │
    │                                │
```

### 18.2 VSCode集成

Claude Code在VSCode中不是"插件"，而是**一级集成**：

- **Session历史**：左侧栏加载历史会话，一键恢复
- **Diff视图**：Agent修改的文件直接在编辑器中显示diff
- **Effort指示器**：输入框边框颜色反映当前推理深度
- **Rate limit可视化**：进度条+重置时间
- **Rewind Picker**：Esc-twice打开对话回退选择器
- **Fork from here**：从历史某个点分叉出新会话

### 18.3 Voice Mode

```
按住说话（push-to-talk）
    │
    ▼
SoX音频捕获 → WebSocket streaming → 语音识别
    │
    ▼
文本进入Agent循环（等同于手动输入）
```

---

## 十九、OpenTelemetry可观测性

Claude Code内置完整的OpenTelemetry集成，覆盖traces、metrics、logs三大支柱：

| 维度 | 采集内容 | 配置 |
|------|---------|------|
| **Events** | tool_decision, tool_result, speed属性 | 自动采集 |
| **Resources** | os.type, os.version, host.arch, wsl.version | 自动采集 |
| **Metrics** | Active Time, token消耗估算, 思考块时长 | 自动采集 |
| **传输** | OTLP over HTTP/gRPC, mTLS支持 | OTEL_*_EXPORTER环境变量 |
| **安全** | 工具参数默认不记录 | `OTEL_LOG_TOOL_DETAILS=1`显式开启 |

Claude Code的11+个官方插件展示了不同的架构模式，对插件开发有直接参考价值：

| 插件 | 架构模式 | 核心组件 | 关键技术 |
|------|---------|---------|---------|
| **feature-dev** | 分阶段多Agent编排 | 1命令+3类Agent | 7阶段工作流、并行Agent、方案对比 |
| **code-review** | 多Agent并行审查 | 1命令+5Agent | 置信度评分、假阳性过滤、GitHub API |
| **ralph-wiggum** | 自迭代反馈循环 | 1命令+Stop Hook | .local.md状态文件、Stop拦截、迭代计数 |
| **security-guidance** | 模式检测防护 | PreToolUse Hook | 9种安全模式、Python脚本分析 |
| **hookify** | 规则引擎生成 | 命令+Agent+Skill | YAML规则、条件匹配、自动生成hooks.json |
| **plugin-dev** | 完整开发套件 | 7Skill+3Agent+命令 | 渐进式信息披露、引导式创建 |
| **pr-review-toolkit** | 专业化Agent组 | 6个审查Agent | 按维度分工（安全/性能/风格/测试） |
| **explanatory-output-style** | 上下文注入 | SessionStart Hook | 改变Claude输出风格 |
| **commit-commands** | 简单命令封装 | 2个Commands | git工作流自动化 |

### 关键模式分析

**模式一：多Agent并行**（code-review、feature-dev）
- 多个Agent并行执行，各自独立
- 主Agent收集结果后综合分析
- 适合需要多角度分析的任务

**模式二：自迭代循环**（ralph-wiggum）
- Stop Hook阻止退出，重新注入prompt
- .local.md文件管理迭代状态
- 适合需要反复改进的任务

**模式三：模式检测**（security-guidance、hookify）
- PreToolUse Hook拦截工具调用
- 正则/规则引擎做快速匹配
- 适合安全防护和合规检查

---

## 二十、与传统AI编程工具的架构对比

| 维度 | Copilot/Cursor | Claude Code |
|------|---------------|-------------|
| **核心交互** | IDE内嵌，代码补全为主 | 终端原生，自然语言为主 |
| **执行模型** | 单次预测，人确认 | Agent循环，自主执行 |
| **能力边界** | IDE API表面决定 | 工具权限+LLM能力+插件生态决定 |
| **扩展方式** | 编写TypeScript插件 | 编写Markdown描述 |
| **安全模型** | IDE沙箱 | 五层纵深防御 |
| **外部集成** | 各自定制 | MCP标准协议 |
| **多步任务** | 人工串联步骤 | Agent自动编排 |
| **自迭代** | 无 | Stop钩子驱动反思循环 |
| **多Agent** | 无 | 并行子Agent+模型差异化 |
| **上下文管理** | 当前文件+邻近文件 | CLAUDE.md层级+Skill条件加载+自动压缩 |

**核心差异：传统工具是"增强人的操作"，Claude Code是"替代人的操作"。** 前者天花板是人的操作效率，后者天花板是Agent的自主决策能力。

从扩展方式看，传统插件是"程序化扩展"——编写确定性代码响应确定性事件；Claude Code插件是"知识化扩展"——编写Markdown描述指导LLM的决策。**从"编程"到"描述"，这是AI时代软件扩展范式的根本变革。**

---

---

## 二十一、性能工程——从CHANGELOG提取的关键数字

架构设计的优劣最终体现在性能数字上。以下是从Claude Code版本演化中提取的关键基准，揭示了每个优化背后的工程权衡：

### 21.1 启动性能

| 优化项 | 效果 | 版本 | 技术手段 |
|--------|------|------|---------|
| 大型repo启动 | 节省 ~80MB内存 | v2.1.80 | 250k文件的repo跳过冗余扫描 |
| 全场景启动 | 节省 ~18MB内存 | v2.1.79 | 惰性加载非关键模块 |
| setup()并行化 | 快 ~30ms | v2.1.84 | 并行初始化独立子系统 |
| macOS密钥链 | 快 ~60ms | v2.1.77 | 批量读取替代逐项查询 |
| Bedrock冷启动 | 显著加速 | v2.1.83 | Profile获取与启动并行 |
| --bare -p模式 | 快 ~14% | v2.1.83 | 跳过hooks/LSP/插件同步/auto-memory |

### 21.2 会话恢复性能

| 优化项 | 效果 | 版本 | 技术手段 |
|--------|------|------|---------|
| --resume大会话 | 快 45% + 省100-150MB峰值内存 | v2.1.77 | 增量加载替代全量反序列化 |
| --resume MCP脱延 | 快 ~600ms | v2.1.79 | 跳过HTTP/SSE MCP重连 |

### 21.3 运行时性能

| 优化项 | 效果 | 版本 | 技术手段 |
|--------|------|------|---------|
| SSE传输 | O(n²) → O(n) | v2.1.90 | 线性缓冲替代累积拼接 |
| SDK转录写入 | O(n²) → O(n) | v2.1.90 | 流式写入替代全量重写 |
| Prompt Cache失效 | 减少12倍token成本 | v2.1.72 | 精确失效替代全量失效 |
| Remote /poll | 请求量减少300倍 | v2.1.72 | 10分钟轮询替代1-2秒 |

### 21.4 系统硬限制

这些不是bug，而是有意的工程边界：

| 限制 | 阈值 | 原因 |
|------|------|------|
| 后台Bash输出 | >5GB被杀 | 防止磁盘耗尽 |
| 脱延工具输入 | >64KB挂起 | 单次传输上限 |
| 工具结果 | >50KB存磁盘 | 避免上下文膨胀 |
| Hook输出 | >50KB存磁盘 | 同上 |
| MCP工具描述 | >2KB截断 | ToolSearch效率 |
| Skill描述 | >250字符截断 | 元数据池大小控制 |
| 上下文使用率 | ≥98%阻止工具调用 | 预留压缩空间 |
| Compaction断路器 | 连续3次失败 | 防止无限token消耗 |
| Streaming空闲 | 90秒超时 | 防止挂起 |
| 会话文件 | >50MB触发消息删除 | 防止OOM |

**这些数字背后的共同原则：宁可提前报错让用户介入，也不让系统在失控状态下持续消耗资源。**

---

## 二十二、系统演化——从CHANGELOG看架构决策

Claude Code的架构不是一次性设计出来的，而是在60+个版本的迭代中逐步演化。以下是关键的架构级变更：

### 22.1 重大架构变更时间线

```
v2.1.72  ┃  Skill与Command合并为统一模型（大重构）
         ┃  ← 之前两者独立，触发机制不同，维护成本高
         ┃  → 之后统一为"Markdown描述 + frontmatter配置"
         ┃
v2.1.76  ┃  Compaction断路器 + PostCompact Hook
         ┃  ← 之前无限重试压缩，导致token浪费
         ┃  → 之后3次失败即停止，给用户可操作的错误
         ┃
v2.1.77  ┃  Agent Teams（实验功能）
         ┃  ← 之前只有SubAgent（主循环内）
         ┃  → 之后支持独立进程的Teammate（tmux生成）
         ┃
v2.1.83  ┃  managed-settings.d/ 分片策略
         ┃  ← 之前单个managed-settings.json
         ┃  → 之后支持多文件按字母序合并（大组织分层治理）
         ┃
v2.1.85  ┃  Deferred权限决策 + Hook条件执行(if字段)
         ┃  ← 之前headless模式遇到ask就卡住
         ┃  → 之后支持暂停→恢复→重新评估
         ┃
v2.1.89  ┃  PermissionDenied Hook + ToolSearch 64KB限制
         ┃  ← 之前权限被拒没有恢复机会
         ┃  → 之后支持 {retry: true} 让模型重试
         ┃
v2.1.90  ┃  SSE/SDK从O(n²)优化到O(n)
         ┃  ← 之前长会话越来越慢（二次方复杂度）
         ┃  → 之后线性处理，长会话不降速
         ┃
v2.1.130 ┃  ToolSearch自动启用（MCP工具 >10%上下文）
         ┃  ← 之前需要手动启用
         ┃  → 之后自动检测并激活
```

### 22.2 内存泄漏修复史（揭示架构薄弱点）

每个修复的内存泄漏都指向架构中资源管理的薄弱环节：

| 版本 | 泄漏原因 | 修复方式 | 架构启示 |
|------|---------|---------|---------|
| v2.1.74 | API流缓冲区未释放 | 显式释放 | 流式处理需要显式生命周期管理 |
| v2.1.74 | Agent完成后状态未回收 | 完成即释放 | SubAgent需要清晰的终止协议 |
| v2.1.74 | Teammate保留完整对话历史 | 只保留摘要 | 长期运行的Agent需要上下文裁剪 |
| v2.1.89 | LRU缓存键保留大JSON输入 | 限制键大小 | 缓存策略需要大小感知 |

### 22.3 Skill/Command合并的设计决策（v2.1.72）

这是Claude Code最大的一次重构，值得深入分析：

```
合并前（v2.1.71及以前）：
    Skill：独立的知识注入机制
        触发：基于description的模糊匹配
        加载：三级渐进式
        位置：skills/*/SKILL.md

    Command：独立的工作流入口
        触发：用户 /command 显式调用
        加载：一次性全量
        位置：commands/*.md

    问题：
    · 两套触发机制，用户难以理解"什么时候用Skill，什么时候用Command"
    · 两套发现逻辑，增加插件开发的认知负担
    · 两套frontmatter规范，容易混淆

合并后（v2.1.72+）：
    统一为"Markdown + frontmatter"模型
    · Command保留 /command 触发方式
    · Skill保留条件匹配触发方式
    · 共享frontmatter规范（allowed-tools, model等）
    · 共享发现逻辑（目录扫描 + 自动注册）
    · Skill增加文件模式匹配 + CLI工具检测触发
    · Skill字符预算 = 上下文窗口的 2%
```

### 22.4 完整Hook事件清单（补充遗漏）

文章前面列了15个Hook事件，但从CHANGELOG中发现还有更多：

| 事件 | 首次出现 | 说明 |
|------|---------|------|
| **PostCompact** | v2.1.76 | 压缩完成后，可注入保留信息 |
| **StopFailure** | v2.1.78 | API错误导致Agent终止时触发 |
| **Elicitation** | v2.1.76 | MCP中间请求拦截（如OAuth步骤） |
| **ElicitationResult** | v2.1.76 | MCP中间请求结果 |

加上之前的15个，**完整的Hook事件数量为19个**。

---

## 二十三、Agent Teams——多Agent协作的高级模式

Agent Teams是Claude Code的实验性功能，代表了多Agent协作的下一步演化。

### 23.1 两种Teammate类型

```
┌─ In-Process Teammate ──────────────────────────┐
│                                                 │
│  · 在主Agent进程内运行                           │
│  · 共享内存空间                                  │
│  · 低延迟通信                                    │
│  · 适用于轻量级、短生命周期的协作任务              │
│                                                 │
└─────────────────────────────────────────────────┘

┌─ Tmux Teammate ────────────────────────────────┐
│                                                 │
│  · 独立进程（通过tmux管理）                       │
│  · 完全隔离的上下文和资源                         │
│  · Shift+Down 导航切换                           │
│  · 适用于长时间运行、资源密集的并行任务             │
│  · Ctrl+F 可杀死所有后台Agent                     │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 23.2 协作事件流

```
主Agent
    │
    ├─ 创建 Teammate（in-process 或 tmux）
    │
    ├─ TeammateIdle Hook ← Teammate空闲时通知主Agent
    │   └─ 可分配新任务或合并结果
    │
    ├─ TaskCompleted Hook ← Teammate完成任务时通知
    │   └─ 收集输出，决定下一步
    │
    └─ 防护机制：
        · 嵌套Agent防护：Teammate不能创建新的Teammate（防止无限递归）
        · 父Agent保留完整历史，Teammate只保留摘要
        · Teammate完成后状态自动释放
```

### 23.3 与SubAgent的区别

| 维度 | SubAgent | Teammate |
|------|---------|----------|
| **进程模型** | 主循环内 | 独立进程（tmux） |
| **上下文共享** | 继承父上下文 | 完全隔离 |
| **生命周期** | 任务完成即释放 | 可长期运行 |
| **通信方式** | 直接返回结果 | 事件驱动（TeammateIdle/TaskCompleted） |
| **适用场景** | 短时间、明确边界的子任务 | 长时间、并行、需要独立环境的协作 |

---

## 二十四、MCP OAuth深度——认证状态机

MCP的OAuth实现不是简单的"跳转→获取token"，而是一个处理多种边缘情况的状态机：

```
初始状态
    │
    ▼
发现阶段
    ├─ RFC 9728：Protected Resource Metadata 自动查找授权服务器
    └─ CIMD：Client ID Metadata Document（无需动态客户端注册）
    │
    ▼
授权阶段
    ├─ 自动：localhost重定向捕获回调
    └─ 手动：重定向失败时的粘贴回调备用方案
    │
    ▼
Token管理
    ├─ 正常：Keychain安全存储 + 自动刷新
    │
    ├─ Step-up Authorization：
    │   服务器返回 403 insufficient_scope
    │   → 自动触发更高权限的重新授权
    │   → 用户在浏览器中确认新scope
    │   → 获取升级后的token
    │
    ├─ 多实例竞态：
    │   多个Claude Code实例同时刷新token
    │   → 只有一个成功，其他使用新token
    │
    └─ Keychain腐坏：
        大型OAuth元数据溢出Keychain缓冲区
        → 自动检测 + 清理 + 重新授权
```

---

## 二十五、Transcript版本控制与会话Fork

### 25.1 Transcript持久化格式

```
~/.claude/sessions/
├── session-abc123.jsonl       ← 消息序列（JSON Lines）
├── session-abc123-results/    ← 大型工具结果文件（>50KB）
└── session-abc123-hooks/      ← 大型Hook输出文件（>50KB）
```

每条消息通过 `parentUuid` 链接形成有向链表：

```
msg-001 (user) → msg-002 (assistant) → msg-003 (tool_result)
                                          │
                                          ├→ msg-004 (继续)
                                          │
                                          └→ msg-004' (fork分支)
```

### 25.2 Fork语义

从任意历史消息点分叉出新的对话分支：

```
原始对话：A → B → C → D → E

从C点Fork：A → B → C → D' → E' → F'
                    │
                    └─ 原始分支：D → E（保留不变）
```

**设计约束**：
- Fork保留分叉点之前的完整上下文
- Fork不复制文件——两个分支共享同一工作目录
- 并发Fork可能争用同一Plan文件（已知边界）
- >5MB的大会话在resume时截断历史（性能保护）

---

## 二十六、架构的局限性与演进方向

不回避问题。Claude Code当前架构有三个结构性限制：

**限制一：延迟链路。** 每次工具调用经过"LLM推理→权限检查→工具执行→结果回传→LLM再推理"的完整链路。读一个文件在终端是毫秒级，在Agent循环中是秒级。简单任务的效率不如直接操作。

**限制二：上下文窗口。** 大型项目的代码量远超任何上下文窗口。CLAUDE.md层级、Skill条件加载、PreCompact钩子都是在缓解而非根本解决。这是所有LLM-based Agent的共同瓶颈。

**限制三：安全模型的不完备性。** 提示钩子依赖LLM判断，而LLM可能被精心构造的输入欺骗（prompt injection）。在关键安全场景中，命令钩子（确定性检查）不可或缺，不能完全依赖LLM的智能判断。

---

## 写在最后

我们正在经历的，不是"给终端加个AI助手"，而是**开发者与代码交互方式的代际跃迁**。

```
补全时代：人写代码 → AI 猜下一行 → 人确认 → 人继续写
Agent时代：人表达意图 → Agent 理解 → Agent 规划 → Agent 执行 → 人审批结果
```

Claude Code的每个工具（Read、Write、Bash、Grep……）都是Agent的"器官"。它的架构是给这些器官加上"大脑"（Agent循环引擎）、"免疫系统"（五层安全模型）、"神经系统"（九大事件钩子）、"生长能力"（插件生态+MCP协议），并把"人操作终端"这层交互替换为"人表达意图，Agent自主执行"。

**底层能力完全继承（文件操作、代码搜索、命令执行），上层范式彻底重塑（从人操作到Agent操作）。**

这不是未来——Claude Code已经在全球开发者的终端里运行了。下一个被重塑的开发工具，可能就是你正在用的那个IDE。
