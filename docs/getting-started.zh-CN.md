# 开始使用

[English](getting-started.md) · Preview **[v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

写给**不一定会写代码**、但想用 AI 做 App 的人。

---

## 产品主路径（先记这个）

```text
  想法
    → 橘猫理解你
    → 生成方案 / 任务包
    → AI 开发（同一文件夹）
    → 验证，再由你决定上线
```

第一天**不必**背命令。用 Mac 时，几乎全程可以用 **Jumao Cat** 应用完成。

---

## 路径 A — Jumao Cat（macOS，推荐）

1. 下载
   [**Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)。
2. 解压 → 把 `Jumao Cat.app` 放进 **「应用程序」** → 从「应用程序」打开。
3. 选择文件夹（空文件夹 = 新想法；已有项目 = 一次改动）。
4. 用普通话回答几道短问题。
5. 确认橘猫理解正确，等待它整理方案。
6. 查看计划（先做什么、守住什么、哪些先不能动）。
7. 点 **「交给 AI Coding Agent」**（说明里会以 Codex、Claude Code、Cursor 等为
   示例，不绑定单一工具）。
8. 在该工具里打开**同一个**文件夹并粘贴指令。
9. Agent 声称做完后，由你决定下一步；对信任的项目可用 CLI 做可选核验。

App 路径**不需要**安装 Node.js。

---

## 路径 B — CLI（开发者 / 非 Mac）

### 安装

```bash
npm install -g jumao@rc
```

请用 **`jumao@rc`**，对应 Preview **0.4.0-rc.2**。

### 开发者主流程

```bash
jumao new "我的第一个App" --dir ./my-first-app
cd ./my-first-app

jumao interview .
jumao check --strict .
jumao audit . --write
jumao pack --target codex .
# 或：--target claude | --target cursor
```

| 步骤 | 含义 |
|------|------|
| `new` | 建文件夹 + 起步产品文件。 |
| `interview` | 用普通话记下目标与边界。 |
| `check --strict` | 关键文件在且非空。 |
| `audit --write` | 写代码前的缺口 / 风险说明。 |
| `pack` | 给 **AI Coding Agent** 的任务包（Codex 只是一种 `--target`）。 |

然后在 Agent 里打开同一文件夹并粘贴任务包。

Agent 做完后（仅信任的项目）：

```bash
jumao verify .
jumao verify . --no-run-checks
```

### 高级诊断（可选）

```bash
jumao doctor .
jumao doctor . --write
```

**`doctor`** 用于更深入的交互式体检，**不是**主流程必经步骤。打包前的标准缺口
报告请用 **`audit`**。

---

## 第一次成功清单

- [ ] 已装 App **或** `jumao@rc`  
- [ ] 已选 / 已建文件夹  
- [ ] 橘猫已理解你的想法（App 问答或 `interview`）  
- [ ] 已有计划或任务包  
- [ ] 已在同一文件夹把包贴给 AI Coding Agent  

第一天不必上架完整商店。

---

## 接着读

- [橘猫如何工作](concepts/how-jumao-works.zh-CN.md)  
- [README](../README.zh-CN.md)  
