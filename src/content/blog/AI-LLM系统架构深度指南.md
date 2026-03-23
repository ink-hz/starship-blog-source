---
title: 'AI/LLM 系统架构深度指南'
description: '深度解析LLM Agent架构设计（ReAct、Plan-and-Execute、Multi-Agent）、推理优化（vLLM、TensorRT-LLM）、RAG检索增强生成及生产级部署实践，含完整代码示例。'
pubDate: 2026-03-23
tags: ['AI技术']
---
# AI/LLM 系统架构深度指南

**学习深度**: ⭐⭐⭐⭐⭐

---

## 第一部分：Agent 架构设计

### 1.1 Agent 基础概念

Agent 是能够感知环境、做出决策并采取行动以实现目标的自主系统。

**LLM Agent 核心组件**:
```
┌─────────────────────────────────────────────┐
│              LLM Agent 架构                  │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │         感知层 (Perception)            │ │
│  │  - 用户输入                            │ │
│  │  - 环境状态                            │ │
│  │  - 历史记忆                            │ │
│  └──────────────┬─────────────────────────┘ │
│                 │                            │
│                 ▼                            │
│  ┌────────────────────────────────────────┐ │
│  │         决策层 (Planning)              │ │
│  │  ┌──────────────────────────────────┐  │ │
│  │  │    大语言模型 (LLM Core)         │  │ │
│  │  │  - 任务理解                      │  │ │
│  │  │  - 推理规划                      │  │ │
│  │  │  - 决策生成                      │  │ │
│  │  └──────────────────────────────────┘  │ │
│  └──────────────┬─────────────────────────┘ │
│                 │                            │
│                 ▼                            │
│  ┌────────────────────────────────────────┐ │
│  │         行动层 (Action)                │ │
│  │  ┌──────────────┐  ┌──────────────┐   │ │
│  │  │   Tools      │  │   Memory     │   │ │
│  │  │  - 搜索引擎  │  │  - 短期记忆  │   │ │
│  │  │  - API调用   │  │  - 长期记忆  │   │ │
│  │  │  - 代码执行  │  │  - 向量数据库│   │ │
│  │  └──────────────┘  └──────────────┘   │ │
│  └──────────────┬─────────────────────────┘ │
│                 │                            │
│                 ▼                            │
│  ┌────────────────────────────────────────┐ │
│  │         反馈层 (Reflection)            │ │
│  │  - 结果验证                            │ │
│  │  - 自我修正                            │ │
│  │  - 经验学习                            │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 1.2 ReAct (Reasoning + Acting) 架构

ReAct 通过交替进行推理和行动来解决问题。

**ReAct 工作流程**:
```
用户问题: "今天北京的天气如何？明天需要带伞吗？"

┌─────────────────────────────────────────────┐
│  Thought 1: 我需要查询北京今天和明天的天气  │
│  Action 1: search("北京天气预报")           │
│  Observation 1: 今天多云 18-25°C,          │
│                 明天有雨 15-20°C            │
├─────────────────────────────────────────────┤
│  Thought 2: 已经获得天气信息，需要分析     │
│             明天下雨，建议带伞               │
│  Action 2: finish("今天北京多云，温度      │
│            18-25°C。明天有雨，建议带伞。")  │
└─────────────────────────────────────────────┘
```

**ReAct Agent 实现**:
```python
from typing import List, Dict, Any, Optional
import json
import re
from openai import OpenAI

class Tool:
    """工具基类"""
    def __init__(self, name: str, description: str):
        self.name = name
        self.description = description

    def execute(self, **kwargs) -> str:
        raise NotImplementedError

class SearchTool(Tool):
    """搜索工具"""
    def __init__(self):
        super().__init__(
            name="search",
            description="搜索互联网获取实时信息。输入: 搜索查询字符串"
        )

    def execute(self, query: str) -> str:
        # 实际应该调用搜索 API（如 Google、Bing）
        # 这里模拟返回结果
        if "天气" in query:
            return "北京今天多云，温度18-25°C。明天有雨，温度15-20°C。"
        return f"搜索结果: {query}"

class CalculatorTool(Tool):
    """计算器工具"""
    def __init__(self):
        super().__init__(
            name="calculator",
            description="执行数学计算。输入: 数学表达式"
        )

    def execute(self, expression: str) -> str:
        try:
            # 安全的数学计算
            result = eval(expression, {"__builtins__": {}}, {})
            return str(result)
        except Exception as e:
            return f"计算错误: {str(e)}"

class PythonREPLTool(Tool):
    """Python 代码执行工具"""
    def __init__(self):
        super().__init__(
            name="python_repl",
            description="执行 Python 代码。输入: Python 代码字符串"
        )

    def execute(self, code: str) -> str:
        try:
            # 在受限环境中执行代码
            exec_globals = {}
            exec(code, {"__builtins__": __builtins__}, exec_globals)

            # 返回最后的表达式结果
            if 'result' in exec_globals:
                return str(exec_globals['result'])
            return "代码执行成功"
        except Exception as e:
            return f"执行错误: {str(e)}"

class ReActAgent:
    """ReAct Agent 实现"""

    def __init__(self, model: str = "gpt-4", max_iterations: int = 10):
        self.client = OpenAI()
        self.model = model
        self.max_iterations = max_iterations
        self.tools: Dict[str, Tool] = {}

    def register_tool(self, tool: Tool):
        """注册工具"""
        self.tools[tool.name] = tool

    def _build_prompt(self, question: str, scratchpad: str) -> str:
        """构建 ReAct 提示词"""
        tools_desc = "\n".join([
            f"- {tool.name}: {tool.description}"
            for tool in self.tools.values()
        ])

        prompt = f"""你是一个问题解决助手。你可以使用以下工具来帮助回答问题:

{tools_desc}

使用以下格式进行推理和行动:

Question: 用户的问题
Thought: 你对如何解决问题的思考
Action: 要执行的动作，格式为 tool_name[input]
Observation: 执行动作后的观察结果
... (重复 Thought/Action/Observation 多次)
Thought: 我现在知道最终答案了
Final Answer: 最终答案

开始！

Question: {question}
{scratchpad}"""
        return prompt

    def _parse_action(self, text: str) -> Optional[tuple]:
        """解析 Action"""
        # 匹配格式: tool_name[input]
        match = re.search(r'Action:\s*(\w+)\[(.*?)\]', text)
        if match:
            tool_name = match.group(1)
            tool_input = match.group(2).strip()
            return (tool_name, tool_input)
        return None

    def _parse_final_answer(self, text: str) -> Optional[str]:
        """解析最终答案"""
        match = re.search(r'Final Answer:\s*(.+)', text, re.DOTALL)
        if match:
            return match.group(1).strip()
        return None

    def run(self, question: str, verbose: bool = True) -> str:
        """运行 ReAct Agent"""
        scratchpad = ""

        for iteration in range(self.max_iterations):
            if verbose:
                print(f"\n{'='*50}")
                print(f"Iteration {iteration + 1}")
                print(f"{'='*50}")

            # 构建提示并调用 LLM
            prompt = self._build_prompt(question, scratchpad)

            response = self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0,
                max_tokens=500
            )

            llm_output = response.choices[0].message.content

            if verbose:
                print(f"\nLLM Output:\n{llm_output}")

            # 检查是否得到最终答案
            final_answer = self._parse_final_answer(llm_output)
            if final_answer:
                if verbose:
                    print(f"\n{'='*50}")
                    print(f"Final Answer: {final_answer}")
                    print(f"{'='*50}")
                return final_answer

            # 解析并执行动作
            action = self._parse_action(llm_output)
            if action:
                tool_name, tool_input = action

                if tool_name not in self.tools:
                    observation = f"错误: 工具 '{tool_name}' 不存在"
                else:
                    tool = self.tools[tool_name]
                    observation = tool.execute(tool_input)

                if verbose:
                    print(f"\nAction: {tool_name}[{tool_input}]")
                    print(f"Observation: {observation}")

                # 更新 scratchpad
                scratchpad += f"\nThought: {llm_output.split('Thought:')[-1].split('Action:')[0].strip()}"
                scratchpad += f"\nAction: {tool_name}[{tool_input}]"
                scratchpad += f"\nObservation: {observation}\n"
            else:
                # 无法解析动作，添加到 scratchpad 让 LLM 继续
                scratchpad += f"\n{llm_output}\n"

        return "达到最大迭代次数，未能找到答案。"

# 使用示例
if __name__ == "__main__":
    # 创建 Agent
    agent = ReActAgent(model="gpt-4", max_iterations=10)

    # 注册工具
    agent.register_tool(SearchTool())
    agent.register_tool(CalculatorTool())
    agent.register_tool(PythonREPLTool())

    # 运行查询
    question = "今天北京的天气如何？明天需要带伞吗？"
    answer = agent.run(question, verbose=True)

    print(f"\n最终答案: {answer}")
```

### 1.3 Plan-and-Execute 架构

Plan-and-Execute 先制定完整计划，然后按步骤执行。

**架构流程**:
```
用户目标: "帮我分析比特币最近一周的价格走势并预测明天的价格"

┌─────────────────────────────────────────────┐
│  Phase 1: Planning (规划阶段)               │
├─────────────────────────────────────────────┤
│  LLM 生成执行计划:                          │
│  1. 获取比特币最近一周的历史价格数据        │
│  2. 计算统计指标(均值、波动率等)           │
│  3. 可视化价格趋势                          │
│  4. 使用时间序列模型预测明天价格           │
│  5. 总结分析结果                            │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Phase 2: Execution (执行阶段)              │
├─────────────────────────────────────────────┤
│  Step 1: [执行中]                           │
│    调用 API 获取价格数据                    │
│    ✓ 完成: 获得 7 天价格数据                │
│                                              │
│  Step 2: [执行中]                           │
│    计算统计指标                              │
│    ✓ 完成: 均值=$42,350, 波动率=3.2%       │
│                                              │
│  Step 3: [执行中]                           │
│    生成价格走势图                            │
│    ✓ 完成: 图表已保存                       │
│                                              │
│  Step 4: [执行中]                           │
│    运行预测模型                              │
│    ✓ 完成: 预测明天价格 $43,100            │
│                                              │
│  Step 5: [执行中]                           │
│    生成分析报告                              │
│    ✓ 完成                                   │
└─────────────────────────────────────────────┘
```

**Plan-and-Execute 实现**:
```python
from typing import List, Dict
from dataclasses import dataclass
from enum import Enum

class StepStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"

@dataclass
class Step:
    """执行步骤"""
    id: int
    description: str
    tool: str
    input: Dict[str, Any]
    status: StepStatus = StepStatus.PENDING
    output: Optional[str] = None
    error: Optional[str] = None

class Planner:
    """规划器 - 负责生成执行计划"""

    def __init__(self, model: str = "gpt-4"):
        self.client = OpenAI()
        self.model = model

    def create_plan(self, objective: str, tools: List[Tool]) -> List[Step]:
        """根据目标创建执行计划"""
        tools_desc = "\n".join([
            f"- {tool.name}: {tool.description}"
            for tool in tools
        ])

        prompt = f"""你是一个任务规划专家。给定一个目标和可用工具，创建详细的执行计划。

可用工具:
{tools_desc}

目标: {objective}

请创建一个分步执行计划，以 JSON 格式返回:
[
  {{
    "step": 1,
    "description": "步骤描述",
    "tool": "工具名称",
    "input": {{"参数": "值"}}
  }},
  ...
]

确保:
1. 步骤之间有逻辑依赖关系
2. 每个步骤都是可执行的
3. 最后一个步骤总结所有结果
"""

        response = self.client.chat.completions.create(
            model=self.model,
            messages=[{"role": "user", "content": prompt}],
            temperature=0
        )

        plan_json = response.choices[0].message.content

        # 解析 JSON (实际应该更健壮)
        import json
        plan_data = json.loads(plan_json)

        steps = []
        for item in plan_data:
            step = Step(
                id=item["step"],
                description=item["description"],
                tool=item["tool"],
                input=item["input"]
            )
            steps.append(step)

        return steps

class Executor:
    """执行器 - 负责执行计划步骤"""

    def __init__(self, tools: Dict[str, Tool]):
        self.tools = tools

    def execute_step(self, step: Step) -> bool:
        """执行单个步骤"""
        step.status = StepStatus.RUNNING

        try:
            if step.tool not in self.tools:
                raise ValueError(f"工具 {step.tool} 不存在")

            tool = self.tools[step.tool]

            # 执行工具
            result = tool.execute(**step.input)

            step.output = result
            step.status = StepStatus.COMPLETED
            return True

        except Exception as e:
            step.error = str(e)
            step.status = StepStatus.FAILED
            return False

class PlanAndExecuteAgent:
    """Plan-and-Execute Agent"""

    def __init__(self, model: str = "gpt-4"):
        self.planner = Planner(model=model)
        self.tools: Dict[str, Tool] = {}

    def register_tool(self, tool: Tool):
        self.tools[tool.name] = tool

    def run(self, objective: str, verbose: bool = True) -> Dict[str, Any]:
        """运行 Agent"""

        # Phase 1: Planning
        if verbose:
            print(f"\n{'='*50}")
            print("Phase 1: Planning")
            print(f"{'='*50}")

        steps = self.planner.create_plan(
            objective,
            list(self.tools.values())
        )

        if verbose:
            print(f"\n执行计划 ({len(steps)} 个步骤):")
            for step in steps:
                print(f"  {step.id}. {step.description}")
                print(f"     工具: {step.tool}")
                print(f"     输入: {step.input}")

        # Phase 2: Execution
        if verbose:
            print(f"\n{'='*50}")
            print("Phase 2: Execution")
            print(f"{'='*50}")

        executor = Executor(self.tools)
        results = []

        for step in steps:
            if verbose:
                print(f"\n执行步骤 {step.id}: {step.description}")

            success = executor.execute_step(step)

            if verbose:
                if success:
                    print(f"  ✓ 完成: {step.output[:100]}...")
                else:
                    print(f"  ✗ 失败: {step.error}")

            results.append({
                "step": step.id,
                "description": step.description,
                "status": step.status.value,
                "output": step.output,
                "error": step.error
            })

            # 如果关键步骤失败，可以选择终止或重试
            if not success and step.id < len(steps):
                print(f"  警告: 步骤 {step.id} 失败，继续执行...")

        return {
            "objective": objective,
            "plan": [
                {"id": s.id, "description": s.description}
                for s in steps
            ],
            "results": results
        }

# 使用示例
if __name__ == "__main__":
    # 创建 Agent
    agent = PlanAndExecuteAgent(model="gpt-4")

    # 注册工具
    agent.register_tool(SearchTool())
    agent.register_tool(CalculatorTool())
    agent.register_tool(PythonREPLTool())

    # 运行任务
    objective = "分析比特币最近一周的价格走势并预测明天的价格"
    result = agent.run(objective, verbose=True)

    print(f"\n最终结果:")
    print(json.dumps(result, indent=2, ensure_ascii=False))
```

### 1.4 Multi-Agent 协作架构

多个专业 Agent 协作完成复杂任务。

**协作模式**:
```
┌──────────────────────────────────────────────────┐
│          Multi-Agent 协作系统                     │
│                                                   │
│  ┌────────────────────────────────────────────┐  │
│  │      协调者 Agent (Coordinator)            │  │
│  │  - 任务分解                                │  │
│  │  - Agent 调度                              │  │
│  │  - 结果聚合                                │  │
│  └──────────┬──────────────────────┬──────────┘  │
│             │                      │              │
│     ┌───────▼──────┐       ┌──────▼────────┐    │
│     │ 研究员 Agent │       │ 分析师 Agent  │    │
│     │ (Researcher) │       │  (Analyst)    │    │
│     │              │       │               │    │
│     │- 信息搜集    │       │- 数据分析     │    │
│     │- 事实核查    │       │- 趋势识别     │    │
│     └───────┬──────┘       └──────┬────────┘    │
│             │                      │              │
│             └──────────┬───────────┘              │
│                        │                          │
│                 ┌──────▼──────────┐               │
│                 │  编辑 Agent     │               │
│                 │  (Editor)       │               │
│                 │                 │               │
│                 │- 内容整合       │               │
│                 │- 质量把控       │               │
│                 └─────────────────┘               │
└──────────────────────────────────────────────────┘
```

**Multi-Agent 实现**:
```python
from abc import ABC, abstractmethod
from typing import List, Dict, Optional

class BaseAgent(ABC):
    """Agent 基类"""

    def __init__(self, name: str, role: str, model: str = "gpt-4"):
        self.name = name
        self.role = role
        self.client = OpenAI()
        self.model = model
        self.memory: List[Dict[str, str]] = []

    @abstractmethod
    def process(self, task: str, context: Optional[Dict] = None) -> str:
        """处理任务"""
        pass

    def _call_llm(self, messages: List[Dict[str, str]]) -> str:
        """调用 LLM"""
        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            temperature=0.7
        )
        return response.choices[0].message.content

class ResearcherAgent(BaseAgent):
    """研究员 Agent - 负责信息搜集"""

    def __init__(self):
        super().__init__(
            name="Researcher",
            role="信息搜集和事实核查专家"
        )
        self.search_tool = SearchTool()

    def process(self, task: str, context: Optional[Dict] = None) -> str:
        """执行研究任务"""
        prompt = f"""你是一个专业的研究员。你的任务是:

{task}

请进行深入研究，收集相关信息并整理成结构化的报告。
确保信息准确、来源可靠。
"""

        messages = [
            {"role": "system", "content": f"你是{self.role}"},
            {"role": "user", "content": prompt}
        ]

        # 先生成研究计划
        research_plan = self._call_llm(messages)

        # 执行搜索（简化版）
        search_results = self.search_tool.execute(task)

        # 整理研究结果
        final_prompt = f"""基于以下搜索结果，整理出结构化的研究报告:

搜索结果:
{search_results}

研究计划:
{research_plan}

请提供详细的研究报告。
"""

        messages.append({"role": "assistant", "content": research_plan})
        messages.append({"role": "user", "content": final_prompt})

        result = self._call_llm(messages)
        self.memory.extend(messages)

        return result

class AnalystAgent(BaseAgent):
    """分析师 Agent - 负责数据分析"""

    def __init__(self):
        super().__init__(
            name="Analyst",
            role="数据分析和趋势识别专家"
        )
        self.calculator = CalculatorTool()

    def process(self, task: str, context: Optional[Dict] = None) -> str:
        """执行分析任务"""
        # 获取研究结果作为输入
        research_data = context.get("research_result", "") if context else ""

        prompt = f"""你是一个专业的数据分析师。你的任务是:

{task}

基于以下研究数据:
{research_data}

请进行深入分析，识别关键趋势和模式。
提供数据支持的洞察和结论。
"""

        messages = [
            {"role": "system", "content": f"你是{self.role}"},
            {"role": "user", "content": prompt}
        ]

        result = self._call_llm(messages)
        self.memory.extend(messages)

        return result

class EditorAgent(BaseAgent):
    """编辑 Agent - 负责内容整合"""

    def __init__(self):
        super().__init__(
            name="Editor",
            role="内容整合和质量把控专家"
        )

    def process(self, task: str, context: Optional[Dict] = None) -> str:
        """整合内容"""
        research_result = context.get("research_result", "") if context else ""
        analysis_result = context.get("analysis_result", "") if context else ""

        prompt = f"""你是一个专业的编辑。你的任务是:

{task}

你需要整合以下内容:

研究报告:
{research_result}

分析结果:
{analysis_result}

请创建一个连贯、专业的最终报告。
确保逻辑清晰、论述充分、结论明确。
"""

        messages = [
            {"role": "system", "content": f"你是{self.role}"},
            {"role": "user", "content": prompt}
        ]

        result = self._call_llm(messages)
        self.memory.extend(messages)

        return result

class CoordinatorAgent(BaseAgent):
    """协调者 Agent - 负责任务分解和调度"""

    def __init__(self):
        super().__init__(
            name="Coordinator",
            role="任务协调和团队管理专家"
        )
        self.agents: Dict[str, BaseAgent] = {}

    def register_agent(self, agent: BaseAgent):
        """注册子 Agent"""
        self.agents[agent.name] = agent

    def process(self, task: str, context: Optional[Dict] = None) -> str:
        """协调多个 Agent 完成任务"""
        print(f"\n协调者: 收到任务 - {task}")

        # Step 1: 研究员收集信息
        print("\n步骤 1: 研究员收集信息")
        researcher = self.agents["Researcher"]
        research_result = researcher.process(
            f"研究以下主题: {task}"
        )
        print(f"研究结果: {research_result[:200]}...")

        # Step 2: 分析师分析数据
        print("\n步骤 2: 分析师分析数据")
        analyst = self.agents["Analyst"]
        analysis_result = analyst.process(
            f"分析研究结果并提供洞察",
            context={"research_result": research_result}
        )
        print(f"分析结果: {analysis_result[:200]}...")

        # Step 3: 编辑整合内容
        print("\n步骤 3: 编辑整合内容")
        editor = self.agents["Editor"]
        final_result = editor.process(
            f"整合研究和分析结果，生成最终报告",
            context={
                "research_result": research_result,
                "analysis_result": analysis_result
            }
        )

        return final_result

# 使用示例
if __name__ == "__main__":
    # 创建协调者
    coordinator = CoordinatorAgent()

    # 创建并注册专业 Agent
    coordinator.register_agent(ResearcherAgent())
    coordinator.register_agent(AnalystAgent())
    coordinator.register_agent(EditorAgent())

    # 执行复杂任务
    task = "分析人工智能在医疗领域的应用现状和未来趋势"
    final_report = coordinator.process(task)

    print(f"\n{'='*50}")
    print("最终报告:")
    print(f"{'='*50}")
    print(final_report)
```

---

## 第二部分：LLM 推理优化

### 2.1 推理性能基础

**推理流程**:
```
输入文本
   │
   ▼
┌─────────────────┐
│ 1. Tokenization │  将文本转换为 token
│    "Hello" -> [15496]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. Embedding    │  token -> 向量
│    [15496] -> [0.1, -0.3, ...] (4096 维)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. Transformer  │  多层注意力计算
│    Layers (×80) │
│                 │
│  ┌────────────┐ │
│  │Self-Attn   │ │  O(n²d) 复杂度
│  ├────────────┤ │
│  │Feed-Forward│ │  O(nd²) 复杂度
│  └────────────┘ │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. Sampling     │  选择下一个 token
│    Logits -> Token
│    [0.3, 0.5, ...] -> "world"
└────────┬────────┘
         │
         ▼
    输出文本
```

**性能瓶颈**:
1. **内存带宽**: 模型权重从 HBM 加载到计算单元
2. **计算量**: 注意力机制的 O(n²) 复杂度
3. **批处理**: 不同请求的序列长度不同

### 2.2 vLLM 架构

vLLM 通过 PagedAttention 实现高效的 KV Cache 管理。

**传统 KV Cache vs PagedAttention**:
```
传统方法 (连续内存分配):
┌─────────────────────────────────────────┐
│  Sequence 1 (500 tokens)                │
│  ┌──────────────────────────────┐       │
│  │ KV Cache (预分配 2048 tokens)│       │
│  │ [Used: 500] [Unused: 1548]   │       │
│  └──────────────────────────────┘       │
│                                          │
│  Sequence 2 (300 tokens)                │
│  ┌──────────────────────────────┐       │
│  │ KV Cache (预分配 2048 tokens)│       │
│  │ [Used: 300] [Unused: 1748]   │       │
│  └──────────────────────────────┘       │
└─────────────────────────────────────────┘
问题: 内存碎片化，浪费 60-80%

PagedAttention (分页管理):
┌─────────────────────────────────────────┐
│  物理内存块 (每块 16 tokens)             │
│  ┌────┐┌────┐┌────┐┌────┐┌────┐        │
│  │ 0  ││ 1  ││ 2  ││ 3  ││ 4  │ ...    │
│  └────┘└────┘└────┘└────┘└────┘        │
│                                          │
│  Sequence 1 逻辑视图 -> 物理块映射       │
│  Token [0-15]   -> Block 0              │
│  Token [16-31]  -> Block 2              │
│  Token [32-47]  -> Block 5              │
│                                          │
│  Sequence 2 逻辑视图 -> 物理块映射       │
│  Token [0-15]   -> Block 1              │
│  Token [16-31]  -> Block 3              │
└─────────────────────────────────────────┘
优势: 接近 100% 内存利用率
```

**vLLM 部署示例**:
```python
# 安装 vLLM
# pip install vllm

from vllm import LLM, SamplingParams

# 初始化模型
llm = LLM(
    model="meta-llama/Llama-2-7b-chat-hf",
    tensor_parallel_size=2,  # 使用 2 块 GPU
    dtype="float16",
    max_model_len=4096,

    # KV Cache 配置
    gpu_memory_utilization=0.9,  # 使用 90% GPU 内存
    swap_space=4,  # 4GB CPU swap 空间

    # PagedAttention 参数
    block_size=16,  # 每个物理块大小
    max_num_seqs=256,  # 最大并发序列数
)

# 采样参数
sampling_params = SamplingParams(
    temperature=0.7,
    top_p=0.9,
    max_tokens=512,

    # 性能优化
    use_beam_search=False,  # 关闭 beam search 以提高吞吐量
    ignore_eos=False
)

# 批量推理
prompts = [
    "Explain the theory of relativity in simple terms.",
    "What are the benefits of regular exercise?",
    "How does photosynthesis work?"
]

# 高吞吐量推理
outputs = llm.generate(prompts, sampling_params)

for output in outputs:
    prompt = output.prompt
    generated_text = output.outputs[0].text
    print(f"Prompt: {prompt}")
    print(f"Generated: {generated_text}\n")
```

**vLLM OpenAI 兼容服务器**:
```bash
# 启动 vLLM 服务器
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-2-7b-chat-hf \
  --tensor-parallel-size 2 \
  --dtype float16 \
  --max-model-len 4096 \
  --gpu-memory-utilization 0.9 \
  --port 8000
```

**客户端调用**:
```python
import openai

# 配置 OpenAI 客户端指向 vLLM 服务器
openai.api_key = "EMPTY"
openai.api_base = "http://localhost:8000/v1"

# 使用标准 OpenAI API
response = openai.ChatCompletion.create(
    model="meta-llama/Llama-2-7b-chat-hf",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain quantum computing."}
    ],
    temperature=0.7,
    max_tokens=512
)

print(response.choices[0].message.content)
```

### 2.3 TensorRT-LLM 优化

NVIDIA TensorRT-LLM 针对 NVIDIA GPU 进行深度优化。

**优化技术**:
```
1. 算子融合 (Operator Fusion)
   ┌─────────┐    ┌─────────┐
   │LayerNorm│ -> │Attention│ -> ...
   └─────────┘    └─────────┘
        ↓ 融合
   ┌─────────────────────┐
   │ Fused LN + Attention│
   └─────────────────────┘
   减少内存访问次数

2. 量化 (Quantization)
   FP16/BF16: 16-bit 浮点数
   INT8: 8-bit 整数 (2x 内存节省, 2x 速度提升)
   INT4: 4-bit 整数 (4x 内存节省)

   FP16: [0.1234, -0.5678, ...]
   INT8: [31, -145, ...]  (量化后)

3. FlashAttention
   标准注意力: O(n²) 内存
   FlashAttention: O(n) 内存
   通过分块计算减少 HBM 访问

4. In-Flight Batching
   动态批处理，实时添加/移除请求
```

**TensorRT-LLM 构建示例**:
```python
# 安装 TensorRT-LLM
# pip install tensorrt_llm

import tensorrt_llm
from tensorrt_llm.builder import Builder
from tensorrt_llm.network import net_guard
from tensorrt_llm.plugin import PluginConfig

# 1. 定义模型配置
model_config = {
    'architecture': 'LlamaForCausalLM',
    'dtype': 'float16',
    'num_layers': 32,
    'num_heads': 32,
    'hidden_size': 4096,
    'vocab_size': 32000,
    'max_position_embeddings': 2048,

    # 优化配置
    'use_gpt_attention_plugin': True,  # 使用优化的 attention
    'use_gemm_plugin': True,  # 使用优化的 GEMM
    'use_layernorm_plugin': True,  # 使用优化的 LayerNorm

    # 量化配置
    'quant_mode': 'int8_weight_only',  # INT8 权重量化
}

# 2. 构建 TensorRT 引擎
builder = Builder()
builder_config = builder.create_builder_config(
    name='llama_7b',
    precision='float16',
    max_batch_size=128,
    max_input_len=1024,
    max_output_len=512,
)

# 3. 构建引擎
with net_guard(builder.create_network()) as network:
    # 加载模型权重
    # ...

    # 构建 TensorRT 引擎
    engine = builder.build_engine(network, builder_config)

# 4. 保存引擎
engine.save('llama_7b_int8.engine')
```

**TensorRT-LLM 推理**:
```python
from tensorrt_llm.runtime import ModelRunner, GenerationSession

# 加载引擎
runner = ModelRunner.from_dir(
    engine_dir='./llama_7b_int8.engine',
    rank=0,  # GPU ID
)

# 准备输入
input_text = "Explain the concept of machine learning"
input_ids = tokenizer.encode(input_text)

# 生成配置
sampling_config = {
    'max_new_tokens': 512,
    'temperature': 0.7,
    'top_k': 50,
    'top_p': 0.9,
    'repetition_penalty': 1.1,
}

# 推理
outputs = runner.generate(
    batch_input_ids=[input_ids],
    sampling_config=sampling_config
)

# 解码输出
output_text = tokenizer.decode(outputs[0])
print(output_text)
```

**性能对比**:
```
Llama-2-7B 推理性能 (A100 GPU):

方法                  吞吐量 (tokens/s)   延迟 (ms)   内存 (GB)
─────────────────────────────────────────────────────────────
Hugging Face          500                 45          14.0
vLLM (FP16)          2,500                12          13.5
TensorRT-LLM (FP16)  3,200                 9          13.0
TensorRT-LLM (INT8)  5,800                 6           7.5
```

### 2.4 推理优化最佳实践

#### 2.4.1 批处理优化

**连续批处理 (Continuous Batching)**:
```python
class ContinuousBatchScheduler:
    """连续批处理调度器"""

    def __init__(self, max_batch_size: int = 32):
        self.max_batch_size = max_batch_size
        self.pending_requests = []
        self.running_batches = []

    def add_request(self, request):
        """添加新请求"""
        self.pending_requests.append(request)

    def schedule(self):
        """调度批次"""
        # 移除已完成的请求
        for batch in self.running_batches:
            batch['requests'] = [
                req for req in batch['requests']
                if not req.is_completed()
            ]

        # 移除空批次
        self.running_batches = [
            batch for batch in self.running_batches
            if len(batch['requests']) > 0
        ]

        # 计算可用空间
        current_batch_size = sum(
            len(batch['requests'])
            for batch in self.running_batches
        )
        available_slots = self.max_batch_size - current_batch_size

        # 添加新请求到批次
        if available_slots > 0 and self.pending_requests:
            new_requests = self.pending_requests[:available_slots]
            self.pending_requests = self.pending_requests[available_slots:]

            if self.running_batches:
                # 添加到现有批次
                self.running_batches[0]['requests'].extend(new_requests)
            else:
                # 创建新批次
                self.running_batches.append({
                    'requests': new_requests,
                    'created_at': time.time()
                })

        return self.running_batches
```

#### 2.4.2 KV Cache 重用

**Prefix Caching**:
```python
class PrefixCache:
    """前缀缓存 - 重用共同的 prompt 前缀"""

    def __init__(self):
        self.cache = {}  # token_ids_hash -> kv_cache

    def get_cached_prefix(self, token_ids):
        """获取最长匹配的前缀缓存"""
        for length in range(len(token_ids), 0, -1):
            prefix = tuple(token_ids[:length])
            prefix_hash = hash(prefix)

            if prefix_hash in self.cache:
                return self.cache[prefix_hash], length

        return None, 0

    def store_prefix(self, token_ids, kv_cache):
        """存储前缀缓存"""
        prefix = tuple(token_ids)
        prefix_hash = hash(prefix)
        self.cache[prefix_hash] = kv_cache

# 使用示例
cache = PrefixCache()

# 第一次请求
prompt1 = "Translate the following English text to French: "
input1 = prompt1 + "Hello, how are you?"
# 生成并缓存 KV cache

# 第二次请求 (重用前缀)
prompt2 = "Translate the following English text to French: "
input2 = prompt2 + "What is your name?"
# 重用前缀的 KV cache，只计算新增部分
```

#### 2.4.3 投机解码 (Speculative Decoding)

使用小模型草稿，大模型验证，加速生成。

```
标准自回归生成:
Step 1: 生成 token 1 (100ms)
Step 2: 生成 token 2 (100ms)
Step 3: 生成 token 3 (100ms)
总时间: 300ms

投机解码:
Step 1: 小模型并行生成 3 个 tokens (30ms)
        draft = [token1, token2, token3]
Step 2: 大模型并行验证 3 个 tokens (100ms)
        accepted = [token1, token2]  (token3 被拒绝)
Step 3: 大模型生成正确的 token 3 (100ms)

总时间: 230ms (加速 23%)
```

```python
class SpeculativeDecoder:
    """投机解码器"""

    def __init__(self, draft_model, target_model, k=4):
        self.draft_model = draft_model  # 小模型
        self.target_model = target_model  # 大模型
        self.k = k  # 草稿长度

    def generate(self, input_ids, max_length=100):
        """投机解码生成"""
        while len(input_ids) < max_length:
            # 1. 小模型生成 k 个草稿 tokens
            draft_tokens = self.draft_model.generate(
                input_ids,
                max_new_tokens=self.k,
                do_sample=True
            )

            # 2. 大模型并行验证
            # 构造验证输入: [input_ids + draft_token[0],
            #                 input_ids + draft_tokens[0:2],
            #                 ...]
            verify_inputs = [
                input_ids + draft_tokens[:i+1]
                for i in range(len(draft_tokens))
            ]

            # 批量并行计算
            verify_probs = self.target_model.compute_probs(verify_inputs)

            # 3. 确定接受的 tokens
            accepted_tokens = []
            for i, (draft_token, target_prob) in enumerate(
                zip(draft_tokens, verify_probs)
            ):
                draft_prob = target_prob[draft_token]

                # 接受概率检查
                if random.random() < draft_prob:
                    accepted_tokens.append(draft_token)
                else:
                    # 从目标分布重新采样
                    new_token = sample_from_probs(target_prob)
                    accepted_tokens.append(new_token)
                    break  # 停止接受后续 tokens

            # 4. 更新序列
            input_ids.extend(accepted_tokens)

            if len(accepted_tokens) < len(draft_tokens):
                # 有 token 被拒绝，已经生成了替代 token
                continue

        return input_ids
```

---

## 第三部分：RAG 系统设计

### 3.1 RAG 基础架构

**RAG (Retrieval-Augmented Generation) 流程**:
```
用户查询: "What are the latest features in Python 3.12?"

┌─────────────────────────────────────────────┐
│  Step 1: 查询理解与改写                      │
├─────────────────────────────────────────────┤
│  原始查询 -> 优化查询                        │
│  "latest features Python 3.12"              │
│  -> "new features introduced Python 3.12    │
│      release notes changelog"               │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Step 2: 向量化检索                          │
├─────────────────────────────────────────────┤
│  查询向量化 (Embedding Model)               │
│  "new features..." -> [0.1, -0.3, ..., 0.5] │
│                                              │
│  向量数据库搜索 (Top-K)                      │
│  ┌──────────────────────────────────────┐  │
│  │ Vector DB (Pinecone/Weaviate/Qdrant)│  │
│  │  Doc 1: Python 3.12 Release (0.95)  │  │
│  │  Doc 2: PEP 695 Type Params (0.89)  │  │
│  │  Doc 3: F-String Syntax (0.85)      │  │
│  └──────────────────────────────────────┘  │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Step 3: 重排序 (Re-ranking)                │
├─────────────────────────────────────────────┤
│  使用交叉编码器 (Cross-Encoder) 精排        │
│  Doc 1: 0.95 -> 0.92                        │
│  Doc 2: 0.89 -> 0.94 (重排后第一)          │
│  Doc 3: 0.85 -> 0.81                        │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Step 4: 上下文构建                          │
├─────────────────────────────────────────────┤
│  Context = Top 3 documents + metadata       │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Step 5: 生成回答                            │
├─────────────────────────────────────────────┤
│  Prompt = f"""                              │
│  Context: {retrieved_docs}                  │
│  Question: {user_query}                     │
│  Answer based on the context above.         │
│  """                                         │
│                                              │
│  LLM (GPT-4/Claude) -> 生成回答             │
└─────────────────────────────────────────────┘
```

### 3.2 RAG 系统实现

**完整 RAG Pipeline**:
```python
from typing import List, Dict, Tuple
import numpy as np
from dataclasses import dataclass
import chromadb
from sentence_transformers import SentenceTransformer, CrossEncoder

@dataclass
class Document:
    """文档数据类"""
    id: str
    content: str
    metadata: Dict[str, any]
    embedding: Optional[np.ndarray] = None

class EmbeddingModel:
    """嵌入模型"""

    def __init__(self, model_name: str = "sentence-transformers/all-MiniLM-L6-v2"):
        self.model = SentenceTransformer(model_name)

    def embed_text(self, text: str) -> np.ndarray:
        """文本向量化"""
        return self.model.encode(text, normalize_embeddings=True)

    def embed_batch(self, texts: List[str]) -> np.ndarray:
        """批量向量化"""
        return self.model.encode(texts, normalize_embeddings=True)

class VectorStore:
    """向量数据库"""

    def __init__(self, collection_name: str = "documents"):
        self.client = chromadb.Client()
        self.collection = self.client.create_collection(
            name=collection_name,
            metadata={"hnsw:space": "cosine"}  # 使用余弦相似度
        )

    def add_documents(self, documents: List[Document]):
        """添加文档"""
        self.collection.add(
            ids=[doc.id for doc in documents],
            embeddings=[doc.embedding.tolist() for doc in documents],
            documents=[doc.content for doc in documents],
            metadatas=[doc.metadata for doc in documents]
        )

    def search(
        self,
        query_embedding: np.ndarray,
        top_k: int = 5,
        filter_dict: Optional[Dict] = None
    ) -> List[Dict]:
        """向量搜索"""
        results = self.collection.query(
            query_embeddings=[query_embedding.tolist()],
            n_results=top_k,
            where=filter_dict  # 元数据过滤
        )

        return [
            {
                "id": results["ids"][0][i],
                "content": results["documents"][0][i],
                "metadata": results["metadatas"][0][i],
                "distance": results["distances"][0][i]
            }
            for i in range(len(results["ids"][0]))
        ]

class Reranker:
    """重排序模型"""

    def __init__(self, model_name: str = "cross-encoder/ms-marco-MiniLM-L-6-v2"):
        self.model = CrossEncoder(model_name)

    def rerank(
        self,
        query: str,
        documents: List[Dict],
        top_k: int = 3
    ) -> List[Dict]:
        """重排序文档"""
        # 构造查询-文档对
        pairs = [(query, doc["content"]) for doc in documents]

        # 计算相关性分数
        scores = self.model.predict(pairs)

        # 添加分数并排序
        for doc, score in zip(documents, scores):
            doc["rerank_score"] = float(score)

        documents.sort(key=lambda x: x["rerank_score"], reverse=True)

        return documents[:top_k]

class QueryRewriter:
    """查询改写器"""

    def __init__(self, llm_client):
        self.client = llm_client

    def rewrite_query(self, query: str, conversation_history: List[Dict] = None) -> str:
        """改写查询以提高检索效果"""
        prompt = f"""你是一个查询优化专家。将以下用户查询改写为更适合检索的形式。

要求:
1. 扩展关键词
2. 添加同义词
3. 补充上下文
4. 保持原意

原始查询: {query}

优化后的查询:"""

        if conversation_history:
            # 考虑对话历史
            history_text = "\n".join([
                f"{msg['role']}: {msg['content']}"
                for msg in conversation_history[-3:]  # 最近3轮
            ])
            prompt = f"对话历史:\n{history_text}\n\n{prompt}"

        response = self.client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3,
            max_tokens=100
        )

        rewritten_query = response.choices[0].message.content.strip()
        return rewritten_query

class RAGPipeline:
    """完整 RAG 流水线"""

    def __init__(
        self,
        embedding_model: EmbeddingModel,
        vector_store: VectorStore,
        reranker: Reranker,
        query_rewriter: Optional[QueryRewriter] = None,
        llm_client = None
    ):
        self.embedding_model = embedding_model
        self.vector_store = vector_store
        self.reranker = reranker
        self.query_rewriter = query_rewriter
        self.llm_client = llm_client or OpenAI()

    def index_documents(self, documents: List[Dict]):
        """索引文档"""
        print(f"索引 {len(documents)} 个文档...")

        # 提取文本内容
        texts = [doc["content"] for doc in documents]

        # 批量嵌入
        embeddings = self.embedding_model.embed_batch(texts)

        # 创建 Document 对象
        docs = [
            Document(
                id=doc.get("id", str(i)),
                content=doc["content"],
                metadata=doc.get("metadata", {}),
                embedding=embeddings[i]
            )
            for i, doc in enumerate(documents)
        ]

        # 添加到向量数据库
        self.vector_store.add_documents(docs)

        print("索引完成!")

    def retrieve(
        self,
        query: str,
        top_k: int = 5,
        rerank_top_k: int = 3,
        filter_dict: Optional[Dict] = None
    ) -> List[Dict]:
        """检索相关文档"""

        # Step 1: 查询改写（可选）
        if self.query_rewriter:
            rewritten_query = self.query_rewriter.rewrite_query(query)
            print(f"原始查询: {query}")
            print(f"改写查询: {rewritten_query}")
            query = rewritten_query

        # Step 2: 向量检索
        query_embedding = self.embedding_model.embed_text(query)
        retrieved_docs = self.vector_store.search(
            query_embedding,
            top_k=top_k,
            filter_dict=filter_dict
        )

        print(f"检索到 {len(retrieved_docs)} 个文档")

        # Step 3: 重排序
        if self.reranker:
            retrieved_docs = self.reranker.rerank(
                query,
                retrieved_docs,
                top_k=rerank_top_k
            )
            print(f"重排序后保留 {len(retrieved_docs)} 个文档")

        return retrieved_docs

    def generate_answer(
        self,
        query: str,
        retrieved_docs: List[Dict],
        model: str = "gpt-4"
    ) -> str:
        """生成答案"""

        # 构建上下文
        context = "\n\n".join([
            f"文档 {i+1} (相关度: {doc.get('rerank_score', doc.get('distance', 0)):.3f}):\n{doc['content']}"
            for i, doc in enumerate(retrieved_docs)
        ])

        # 构建提示
        prompt = f"""请基于以下文档回答用户问题。

检索到的文档:
{context}

用户问题: {query}

要求:
1. 仅基于提供的文档内容回答
2. 如果文档中没有相关信息，明确说明
3. 引用具体的文档编号
4. 保持客观和准确

回答:"""

        # 调用 LLM
        response = self.llm_client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "你是一个基于文档的问答助手。"},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3,
            max_tokens=500
        )

        answer = response.choices[0].message.content
        return answer

    def query(
        self,
        question: str,
        top_k: int = 5,
        rerank_top_k: int = 3,
        return_sources: bool = True
    ) -> Dict[str, any]:
        """完整的 RAG 查询"""

        print(f"\n{'='*50}")
        print(f"查询: {question}")
        print(f"{'='*50}\n")

        # 检索文档
        retrieved_docs = self.retrieve(
            question,
            top_k=top_k,
            rerank_top_k=rerank_top_k
        )

        # 生成答案
        answer = self.generate_answer(question, retrieved_docs)

        result = {
            "question": question,
            "answer": answer,
        }

        if return_sources:
            result["sources"] = retrieved_docs

        return result

# 使用示例
if __name__ == "__main__":
    from openai import OpenAI

    # 初始化组件
    embedding_model = EmbeddingModel()
    vector_store = VectorStore(collection_name="knowledge_base")
    reranker = Reranker()
    query_rewriter = QueryRewriter(OpenAI())

    # 创建 RAG Pipeline
    rag = RAGPipeline(
        embedding_model=embedding_model,
        vector_store=vector_store,
        reranker=reranker,
        query_rewriter=query_rewriter
    )

    # 索引文档
    documents = [
        {
            "id": "doc1",
            "content": "Python 3.12 introduces several new features including PEP 695 for type parameter syntax, improved error messages, and performance enhancements.",
            "metadata": {"source": "python_docs", "version": "3.12"}
        },
        {
            "id": "doc2",
            "content": "The new type parameter syntax in Python 3.12 allows for more concise generic class definitions using square brackets.",
            "metadata": {"source": "pep_695", "version": "3.12"}
        },
        # 更多文档...
    ]

    rag.index_documents(documents)

    # 查询
    result = rag.query(
        "What are the new features in Python 3.12?",
        top_k=5,
        rerank_top_k=3
    )

    print(f"\n{'='*50}")
    print("回答:")
    print(f"{'='*50}")
    print(result["answer"])

    print(f"\n{'='*50}")
    print("来源文档:")
    print(f"{'='*50}")
    for i, source in enumerate(result["sources"]):
        print(f"\n文档 {i+1}:")
        print(f"  相关度: {source.get('rerank_score', 0):.3f}")
        print(f"  内容: {source['content'][:200]}...")
```

### 3.3 高级 RAG 技术

#### 3.3.1 Hybrid Search (混合搜索)

结合向量搜索和关键词搜索。

```python
class HybridSearchRAG:
    """混合搜索 RAG"""

    def __init__(self, vector_store, bm25_index):
        self.vector_store = vector_store
        self.bm25_index = bm25_index  # BM25 关键词索引

    def hybrid_search(
        self,
        query: str,
        top_k: int = 10,
        alpha: float = 0.5  # 向量搜索权重
    ) -> List[Dict]:
        """混合搜索"""

        # 向量搜索
        vector_results = self.vector_store.search(query, top_k=top_k*2)

        # BM25 关键词搜索
        bm25_results = self.bm25_index.search(query, top_k=top_k*2)

        # 归一化分数
        vector_scores = self._normalize_scores([r["distance"] for r in vector_results])
        bm25_scores = self._normalize_scores([r["score"] for r in bm25_results])

        # 合并分数
        all_docs = {}

        for doc, score in zip(vector_results, vector_scores):
            doc_id = doc["id"]
            all_docs[doc_id] = {
                "doc": doc,
                "score": alpha * score
            }

        for doc, score in zip(bm25_results, bm25_scores):
            doc_id = doc["id"]
            if doc_id in all_docs:
                all_docs[doc_id]["score"] += (1 - alpha) * score
            else:
                all_docs[doc_id] = {
                    "doc": doc,
                    "score": (1 - alpha) * score
                }

        # 排序并返回 top-k
        ranked_docs = sorted(
            all_docs.values(),
            key=lambda x: x["score"],
            reverse=True
        )[:top_k]

        return [item["doc"] for item in ranked_docs]

    def _normalize_scores(self, scores: List[float]) -> List[float]:
        """归一化分数到 [0, 1]"""
        min_score = min(scores)
        max_score = max(scores)
        if max_score == min_score:
            return [1.0] * len(scores)
        return [(s - min_score) / (max_score - min_score) for s in scores]
```

#### 3.3.2 Parent-Child Chunking

使用小块检索，大块生成。

```
文档结构:
┌─────────────────────────────────────┐
│  Parent Chunk (大块)                │
│  ┌──────────────────────────────┐  │
│  │  Child Chunk 1 (小块)        │  │
│  │  "Python 3.12 introduces..." │  │  <- 用于检索
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │  Child Chunk 2               │  │
│  │  "The new type parameter..." │  │  <- 用于检索
│  └──────────────────────────────┘  │
│                                     │  <- 用于生成
│  完整上下文包含更多细节...          │
└─────────────────────────────────────┘

检索流程:
1. 向量搜索匹配 Child Chunk 1
2. 返回对应的 Parent Chunk 给 LLM
3. 保留更多上下文信息
```

```python
class ParentChildRAG:
    """父子分块 RAG"""

    def chunk_document(self, document: str, parent_size: int = 1000, child_size: int = 200):
        """分块文档"""
        chunks = []

        # 创建父块
        for i in range(0, len(document), parent_size):
            parent_chunk = document[i:i+parent_size]
            parent_id = f"parent_{i}"

            # 在父块内创建子块
            child_chunks = []
            for j in range(0, len(parent_chunk), child_size):
                child_chunk = parent_chunk[j:j+child_size]
                child_id = f"child_{i}_{j}"

                child_chunks.append({
                    "id": child_id,
                    "content": child_chunk,
                    "parent_id": parent_id
                })

            chunks.append({
                "parent": {
                    "id": parent_id,
                    "content": parent_chunk
                },
                "children": child_chunks
            })

        return chunks

    def retrieve(self, query: str, top_k: int = 3):
        """检索"""
        # 1. 搜索子块
        child_results = self.vector_store.search(query, top_k=top_k*2)

        # 2. 获取对应的父块（去重）
        parent_ids = set(r["metadata"]["parent_id"] for r in child_results)
        parent_chunks = [
            self.parent_store.get(parent_id)
            for parent_id in list(parent_ids)[:top_k]
        ]

        return parent_chunks
```

#### 3.3.3 Self-RAG (自我反思 RAG)

Agent 自主判断是否需要检索。

```python
class SelfRAG:
    """Self-RAG 系统"""

    def __init__(self, rag_pipeline, llm_client):
        self.rag = rag_pipeline
        self.llm = llm_client

    def need_retrieval(self, query: str, conversation_history: List[Dict]) -> bool:
        """判断是否需要检索"""
        prompt = f"""判断以下用户问题是否需要检索外部知识。

问题: {query}

如果问题满足以下条件之一，回答 "YES":
1. 需要最新信息
2. 需要专业知识
3. 需要特定事实

否则回答 "NO"

回答 (YES/NO):"""

        response = self.llm.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            temperature=0,
            max_tokens=10
        )

        decision = response.choices[0].message.content.strip().upper()
        return decision == "YES"

    def generate_with_reflection(self, query: str, max_iterations: int = 3):
        """带反思的生成"""

        # 判断是否需要检索
        if not self.need_retrieval(query, []):
            # 直接生成
            return self._direct_generate(query)

        # RAG 生成
        for iteration in range(max_iterations):
            # 检索并生成
            result = self.rag.query(query)
            answer = result["answer"]

            # 自我评估
            is_good, feedback = self._self_evaluate(query, answer, result["sources"])

            if is_good:
                return answer
            else:
                # 根据反馈改进查询
                query = self._refine_query(query, feedback)
                print(f"迭代 {iteration + 1}: 改进查询为 '{query}'")

        return answer

    def _self_evaluate(self, query: str, answer: str, sources: List[Dict]) -> Tuple[bool, str]:
        """自我评估答案质量"""
        prompt = f"""评估以下答案的质量:

问题: {query}

答案: {answer}

评估标准:
1. 答案是否直接回答了问题
2. 答案是否有事实依据
3. 答案是否完整

如果答案质量好，回答 "GOOD"
否则回答 "BAD: [改进建议]"

评估:"""

        response = self.llm.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            temperature=0
        )

        evaluation = response.choices[0].message.content.strip()

        if evaluation.startswith("GOOD"):
            return True, ""
        else:
            feedback = evaluation.replace("BAD:", "").strip()
            return False, feedback
```

---

## 第四部分：模型路由与负载均衡

### 4.1 智能路由架构

**路由策略**:
```
用户请求
   │
   ▼
┌─────────────────────────────────────┐
│      路由决策层                      │
│  ┌────────────────────────────────┐ │
│  │  1. 任务分类                   │ │
│  │     - 简单问答 -> GPT-3.5     │ │
│  │     - 复杂推理 -> GPT-4       │ │
│  │     - 代码生成 -> Claude      │ │
│  │                                │ │
│  │  2. 成本优化                   │ │
│  │     - 预算限制                 │ │
│  │     - Token 数优化             │ │
│  │                                │ │
│  │  3. 性能优化                   │ │
│  │     - 负载均衡                 │ │
│  │     - 延迟最小化               │ │
│  └────────────────────────────────┘ │
└──────────┬──────────────────────────┘
           │
    ┌──────┼──────┐
    │      │      │
    ▼      ▼      ▼
┌───────┐┌───────┐┌───────┐
│GPT-3.5││GPT-4  ││Claude │
│实例池 ││实例池 ││实例池 │
│(10个) ││(5个)  ││(3个)  │
└───────┘└───────┘└───────┘
```

### 4.2 模型路由器实现

```python
from enum import Enum
from typing import Optional, List, Dict
import time
from collections import deque
import asyncio

class ModelTier(Enum):
    """模型层级"""
    FAST = "fast"        # 快速、便宜 (GPT-3.5)
    BALANCED = "balanced"  # 平衡 (GPT-4-turbo)
    POWERFUL = "powerful"  # 强大、昂贵 (GPT-4, Claude-3-Opus)
    SPECIALIZED = "specialized"  # 专用 (Code-specific, etc.)

class TaskComplexity(Enum):
    """任务复杂度"""
    SIMPLE = "simple"
    MEDIUM = "medium"
    COMPLEX = "complex"

class ModelEndpoint:
    """模型端点"""

    def __init__(
        self,
        name: str,
        tier: ModelTier,
        api_key: str,
        base_url: str,
        max_requests_per_minute: int = 60,
        cost_per_1k_tokens: float = 0.001
    ):
        self.name = name
        self.tier = tier
        self.api_key = api_key
        self.base_url = base_url
        self.max_rpm = max_requests_per_minute
        self.cost_per_1k_tokens = cost_per_1k_tokens

        # 速率限制
        self.request_times = deque(maxlen=max_requests_per_minute)

        # 监控指标
        self.total_requests = 0
        self.total_tokens = 0
        self.total_cost = 0.0
        self.latencies = []

    async def can_accept_request(self) -> bool:
        """检查是否可以接受请求"""
        now = time.time()

        # 清理超过1分钟的请求记录
        while self.request_times and now - self.request_times[0] > 60:
            self.request_times.popleft()

        return len(self.request_times) < self.max_rpm

    async def generate(self, prompt: str, **kwargs) -> Dict:
        """生成响应"""
        # 等待速率限制
        while not await self.can_accept_request():
            await asyncio.sleep(0.1)

        start_time = time.time()
        self.request_times.append(start_time)

        # 调用实际的 API (这里简化)
        # response = await call_model_api(self.base_url, prompt, **kwargs)

        # 模拟响应
        response = {
            "text": f"Response from {self.name}",
            "tokens": len(prompt.split()) * 2,
            "model": self.name
        }

        # 更新指标
        latency = time.time() - start_time
        self.latencies.append(latency)
        self.total_requests += 1
        self.total_tokens += response["tokens"]
        self.total_cost += (response["tokens"] / 1000) * self.cost_per_1k_tokens

        return response

    def get_avg_latency(self) -> float:
        """获取平均延迟"""
        if not self.latencies:
            return 0.0
        return sum(self.latencies[-100:]) / min(len(self.latencies), 100)

class ComplexityClassifier:
    """任务复杂度分类器"""

    def __init__(self, llm_client):
        self.client = llm_client

    async def classify(self, query: str) -> TaskComplexity:
        """分类任务复杂度"""
        prompt = f"""分类以下任务的复杂度:

任务: {query}

复杂度级别:
- SIMPLE: 简单问答、事实查询、基本对话
- MEDIUM: 需要推理、分析、总结
- COMPLEX: 复杂推理、创意写作、深度分析

回答 (SIMPLE/MEDIUM/COMPLEX):"""

        response = await self.client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            temperature=0,
            max_tokens=10
        )

        complexity_str = response.choices[0].message.content.strip().upper()

        try:
            return TaskComplexity[complexity_str]
        except KeyError:
            return TaskComplexity.MEDIUM  # 默认中等复杂度

class ModelRouter:
    """智能模型路由器"""

    def __init__(self):
        self.endpoints: Dict[ModelTier, List[ModelEndpoint]] = {
            tier: [] for tier in ModelTier
        }
        self.complexity_classifier = None

    def register_endpoint(self, endpoint: ModelEndpoint):
        """注册模型端点"""
        self.endpoints[endpoint.tier].append(endpoint)

    def set_classifier(self, classifier: ComplexityClassifier):
        """设置复杂度分类器"""
        self.complexity_classifier = classifier

    async def route(
        self,
        query: str,
        preferred_tier: Optional[ModelTier] = None,
        max_cost: Optional[float] = None,
        max_latency: Optional[float] = None
    ) -> Dict:
        """路由请求到最佳模型"""

        # Step 1: 如果没有指定层级，自动分类
        if preferred_tier is None and self.complexity_classifier:
            complexity = await self.complexity_classifier.classify(query)

            # 根据复杂度选择层级
            tier_mapping = {
                TaskComplexity.SIMPLE: ModelTier.FAST,
                TaskComplexity.MEDIUM: ModelTier.BALANCED,
                TaskComplexity.COMPLEX: ModelTier.POWERFUL
            }
            preferred_tier = tier_mapping[complexity]
        elif preferred_tier is None:
            preferred_tier = ModelTier.BALANCED

        # Step 2: 获取该层级的端点
        candidates = self.endpoints.get(preferred_tier, [])

        if not candidates:
            # 降级到其他层级
            for tier in ModelTier:
                if self.endpoints[tier]:
                    candidates = self.endpoints[tier]
                    break

        if not candidates:
            raise RuntimeError("没有可用的模型端点")

        # Step 3: 根据约束条件筛选
        if max_cost:
            candidates = [
                ep for ep in candidates
                if ep.cost_per_1k_tokens <= max_cost
            ]

        if max_latency:
            candidates = [
                ep for ep in candidates
                if ep.get_avg_latency() <= max_latency
            ]

        # Step 4: 负载均衡选择
        # 策略: 选择当前请求数最少的端点
        selected = min(
            candidates,
            key=lambda ep: len(ep.request_times)
        )

        print(f"路由到: {selected.name} (Tier: {selected.tier.value})")

        # Step 5: 生成响应
        response = await selected.generate(query)

        return {
            "response": response,
            "model_used": selected.name,
            "tier": selected.tier.value,
            "cost": (response["tokens"] / 1000) * selected.cost_per_1k_tokens
        }

# 使用示例
async def main():
    # 创建路由器
    router = ModelRouter()

    # 注册端点
    # FAST 层级
    for i in range(10):
        router.register_endpoint(ModelEndpoint(
            name=f"gpt-3.5-turbo-{i}",
            tier=ModelTier.FAST,
            api_key="sk-xxx",
            base_url="https://api.openai.com/v1",
            max_requests_per_minute=60,
            cost_per_1k_tokens=0.0015
        ))

    # BALANCED 层级
    for i in range(5):
        router.register_endpoint(ModelEndpoint(
            name=f"gpt-4-turbo-{i}",
            tier=ModelTier.BALANCED,
            api_key="sk-xxx",
            base_url="https://api.openai.com/v1",
            max_requests_per_minute=40,
            cost_per_1k_tokens=0.01
        ))

    # POWERFUL 层级
    for i in range(3):
        router.register_endpoint(ModelEndpoint(
            name=f"claude-3-opus-{i}",
            tier=ModelTier.POWERFUL,
            api_key="sk-xxx",
            base_url="https://api.anthropic.com/v1",
            max_requests_per_minute=20,
            cost_per_1k_tokens=0.015
        ))

    # 设置分类器
    classifier = ComplexityClassifier(OpenAI())
    router.set_classifier(classifier)

    # 测试路由
    queries = [
        "What is 2+2?",  # SIMPLE -> FAST
        "Explain quantum entanglement",  # MEDIUM -> BALANCED
        "Write a comprehensive analysis of macroeconomic trends",  # COMPLEX -> POWERFUL
    ]

    for query in queries:
        result = await router.route(query)
        print(f"\nQuery: {query}")
        print(f"Model: {result['model_used']}")
        print(f"Cost: ${result['cost']:.6f}")

if __name__ == "__main__":
    asyncio.run(main())
```

### 4.3 Anthropic MCP (Model Context Protocol)

MCP 是一个标准协议，用于应用程序和 AI 模型之间的上下文共享。

**MCP 架构**:
```
┌─────────────────────────────────────────┐
│         应用程序 (Host)                  │
│  ┌───────────────────────────────────┐  │
│  │      MCP Client                   │  │
│  └──────────┬────────────────────────┘  │
└───────────┼─────────────────────────────┘
            │ MCP Protocol
            │ (JSON-RPC over stdio/HTTP)
            │
    ┌───────┼───────┐
    │       │       │
    ▼       ▼       ▼
┌────────┐┌────────┐┌────────┐
│MCP     ││MCP     ││MCP     │
│Server 1││Server 2││Server 3│
│        ││        ││        │
│文件系统││数据库  ││API调用 │
└────────┘└────────┘└────────┘
```

**MCP Server 示例** (Python):
```python
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types

# 创建 MCP Server
server = Server("example-server")

@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """列出可用工具"""
    return [
        types.Tool(
            name="read_file",
            description="读取文件内容",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "文件路径"
                    }
                },
                "required": ["path"]
            }
        ),
        types.Tool(
            name="search_web",
            description="搜索互联网",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索查询"
                    }
                },
                "required": ["query"]
            }
        )
    ]

@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict
) -> list[types.TextContent]:
    """执行工具调用"""

    if name == "read_file":
        path = arguments["path"]
        try:
            with open(path, 'r') as f:
                content = f.read()
            return [types.TextContent(
                type="text",
                text=content
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error reading file: {str(e)}"
            )]

    elif name == "search_web":
        query = arguments["query"]
        # 实现搜索逻辑
        results = f"Search results for: {query}"
        return [types.TextContent(
            type="text",
            text=results
        )]

    else:
        raise ValueError(f"Unknown tool: {name}")

@server.list_resources()
async def handle_list_resources() -> list[types.Resource]:
    """列出可用资源"""
    return [
        types.Resource(
            uri="file:///workspace/project",
            name="Project Files",
            description="Access to project files",
            mimeType="application/x-directory"
        )
    ]

@server.read_resource()
async def handle_read_resource(uri: str) -> str:
    """读取资源"""
    # 实现资源读取逻辑
    return f"Content of {uri}"

# 运行服务器
async def main():
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="example-server",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={}
                )
            )
        )

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

**MCP Client 使用**:
```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def use_mcp_tools():
    """使用 MCP 工具"""

    # 连接到 MCP Server
    server_params = StdioServerParameters(
        command="python",
        args=["mcp_server.py"]
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            # 初始化
            await session.initialize()

            # 列出可用工具
            tools = await session.list_tools()
            print(f"可用工具: {[t.name for t in tools]}")

            # 调用工具
            result = await session.call_tool(
                "read_file",
                {"path": "/tmp/example.txt"}
            )

            print(f"结果: {result.content[0].text}")

            # 集成到 LLM
            llm_tools = [
                {
                    "type": "function",
                    "function": {
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.inputSchema
                    }
                }
                for tool in tools
            ]

            # 使用 LLM 调用工具
            response = await call_llm_with_tools(llm_tools, session)

asyncio.run(use_mcp_tools())
```

---

## 总结与最佳实践

### Agent 架构选择

| 架构类型 | 适用场景 | 优势 | 劣势 |
|---------|---------|------|------|
| ReAct | 需要动态决策的任务 | 灵活、透明 | 可能陷入循环 |
| Plan-and-Execute | 已知流程的复杂任务 | 可预测、高效 | 缺乏灵活性 |
| Multi-Agent | 多领域专业任务 | 专业化、可扩展 | 协调复杂度高 |

### LLM 推理优化

1. **使用 vLLM**: 适合高并发场景，PagedAttention 大幅提升吞吐量
2. **使用 TensorRT-LLM**: 适合 NVIDIA GPU，极致性能
3. **量化**: INT8/INT4 量化可节省50-75%内存
4. **Speculative Decoding**: 对延迟敏感场景可加速 20-30%

### RAG 系统设计

1. **混合搜索**: 向量 + 关键词，提升召回率
2. **重排序**: 必须使用，可提升 15-30% 准确率
3. **Parent-Child**: 平衡检索精度和上下文完整性
4. **Self-RAG**: 减少不必要的检索，降低成本

### 模型路由

1. **按复杂度路由**: 简单任务用 GPT-3.5，节省 90% 成本
2. **负载均衡**: 多实例提升并发能力
3. **降级策略**: 高层级不可用时自动降级

---

## 参考资源

- **LangChain 架构**: https://python.langchain.com/docs/concepts/architecture
- **OpenAI Agent 最佳实践**: https://platform.openai.com/docs/guides/agents
- **vLLM 文档**: https://docs.vllm.ai/
- **TensorRT-LLM**: https://github.com/NVIDIA/TensorRT-LLM
- **Anthropic MCP**: https://modelcontextprotocol.io/
- **RAG 论文**: https://arxiv.org/abs/2005.11401
- **ReAct 论文**: https://arxiv.org/abs/2210.03629
