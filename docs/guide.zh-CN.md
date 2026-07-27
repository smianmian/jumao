# 橘猫使用指南

**当前公开 Preview：[v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

橘猫帮你在让 AI 写代码**之前**，先把产品想清楚。

## 推荐路径：Jumao Cat（macOS）

多数人请从 App 开始：

1. 从
   [v0.4.0-rc.2 发布页](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)
   安装 Preview（或 CLI：`npm install -g jumao@rc`）。
2. 选择新文件夹或已有项目。
3. 回答几道普通语言的问题。
4. 确认理解后，让本地规划跑完。
5. 把计划交给 Codex / Claude Code / Cursor，在**同一个**项目文件夹里粘贴指令。

安装链接和完整 App 流程见主 [README](../README.zh-CN.md)。

## 为什么需要这一步

AI 编程工具很快。如果没有清楚的首版目标、边界和验收证据，它容易扩大范围、
自己加功能，或没有证据就说「做完了」。橘猫是本地规划步骤，让交给 AI 的任务
更小、可核对。

## CLI 路径（同一套 Runtime）

```bash
npm install -g jumao@rc
jumao interview /你的/项目路径   # 默认聚焦问题
jumao plan /你的/项目路径
# AI 干完后：
jumao verify /你的/项目路径      # 只对信任的项目
```

主要交接文件通常是 `tasks/jumao-agent-plan.md`。

## 可选的产品文件（进阶 / 模板）

部分流程仍会用 `product/`、`proof/` 下的产品文档（简报、范围、页面状态、
数据安全、发布证据）。它们适合当**给人看的产品记录**，也给 `jumao pack`
任务包用。对 Jumao Cat / `jumao plan` 的聚焦 Preview 路径来说，**不是必填**。

可复制提示词见 [AI 提示词](prompts.zh-CN.md)。

## 怎么判断 AI 没有跑偏

每次改完问三句：

1. 对应哪个用户目标？
2. 有什么证据证明完成？
3. 会不会影响真实用户、钱、审核、上线或生产数据？

说不清就先停下。

## 旧版本

**v0.3.1** 及更早版本仅作历史对照。新用户请从 **v0.4.0-rc.2 Preview**
（`jumao@rc` 或 macOS Preview 包）开始，不要再把旧稳定线当入口。
