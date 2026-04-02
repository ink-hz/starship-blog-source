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

### 8.3 上下文压缩策略

```
上下文接近窗口限制
    │
    ▼
触发 PreCompact Hook → 保留关键信息
    │
    ▼
自动紧凑执行：
    ├─ 移除非关键的中间消息
    ├─ 合并重复的工具输出
    ├─ 保留：CLAUDE.md、Skill指令、钩子规则、架构决策
    ├─ 压缩：工具中间输出、搜索结果、文件内容
    │
    ▼
抖动循环检测：
    └─ 连续3次紧凑后仍超限 → 停止并显示可操作错误
       （防止无限烧费API调用）
```

---

## 九、官方插件架构模式参考

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

## 十、与传统AI编程工具的架构对比

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

## 十一、架构的局限性与演进方向

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
