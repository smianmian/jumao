# 橘猫如何工作

[English](how-jumao-works.md) · [开始使用](../getting-started.zh-CN.md)

本页**不是**首页。在理解产品主路径之后再读：

**想法 → 橘猫理解 → 方案 / 任务包 → AI 开发 → 验证 → 你决定上线。**

---

## 同一产品的两种说法

**普通人：** 橘猫帮不会写代码的人，用 AI 把 App 从想法往可交付推进——先钉计划，
再让 AI 写代码。

**开发者：** 橘猫是 AI Coding Agent 的**决策和交付控制层**。改仓库的仍是 Agent；
橘猫管目标、范围、证据、审计和交给 Agent 的任务包。

```text
  你（目标；真实世界的拍板）
       │
       ▼
  橘猫（决策 + 打包 + 可选核验）
       │
       ▼
  AI Coding Agent（实现 — 如 Codex、Claude Code、Cursor）
       │
       ▼
  本机 / 商店（上线仍是你）
```

不绑定单一厂商。`pack --target codex|claude|cursor` 只是格式；产品动作是
**交给 AI Coding Agent**。

---

## 核心概念

### Goal（目标）

这一版要让真实用户得到什么，以及怎样算完成。

### Evidence（证据）

证明「真的如此 / 真的做完」：产品文件、测试、日志、截图、完成回执。没有证据的
「做完了」不算完成。

### Scope（范围）

这一版**做什么**、**不做什么**。明确的「先不做」拦住 Agent 乱扩功能。

### Audit（审计）

写代码前的结构化缺口 / 风险查看（`jumao audit`），常写入 `governance/`。

**`jumao doctor`** 是**高级、交互式诊断**，适合想要引导式体检时使用，**不是**
主流程必经步骤。

### Pack（任务包）

`jumao pack --target …` 生成的任务包——边界、门禁、下一步安全工作。橘猫进入
Agent 的主桥梁。

### Execution Boundary（执行边界）

Agent **现在**可以做什么（通常是本地准备与验证），以及什么必须等你确认（生产、
真实支付、商店提审、不可逆线上数据）。

规划与打包默认**本地**，不依赖橘猫云端 AI API。

---

## CLI 对照（开发者路径）

| 步骤 | 命令 | 控制层职责 |
|------|------|------------|
| 安家 | `jumao new` | 工作区 + 起步文件 |
| 记意图 | `jumao interview` | 目标与范围 |
| 门禁 | `jumao check --strict` | 关键产物在场 |
| 审计 | `jumao audit --write` | 写代码前的缺口 |
| 交接 | `jumao pack --target …` | 给 AI Coding Agent 的包 |
| （可选）规划 | `jumao plan` / Jumao Cat | 本地规划与可读计划 |
| （可选）深诊 | `jumao doctor` | 高级诊断 |
| （Agent 之后） | `jumao verify` | 核完成说法 |

---

## 橘猫管不到的事

- 写具体业务 / 界面代码（编程工具）  
- 你的产品品味  
- 商店与云账号、主体与合同  

---

## 安全

- 检查 / 规划默认只读源码  
- 完整 `jumao verify` 可能跑项目测试——只对信任的树  
- 真实用户、钱、审核、生产仍须人确认  

---

## 相关

- [开始使用](../getting-started.zh-CN.md)  
- [README](../../README.zh-CN.md)  
