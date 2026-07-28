# Jumao 橘猫

[English](README.md)

**Preview · [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

## 橘猫是什么？

你不一定会写代码，也可以靠 AI 把 App 想法做出来。

**橘猫（Jumao Cat）**帮你把「想做什么」——或「已有项目这次要改成什么样」——整理成
一份说得清、有依据、能交给 AI 编程工具的开发计划。然后再把计划交给 Codex、
Claude Code、Cursor 等工具去写代码。

AI 擅长敲代码，不擅长守边界：容易越做越大、漏掉「这版先不做」、也缺少完成证据。
橘猫是**写代码之前**的一步：先把想法理清、看一眼项目、写出 AI 能跟着走的计划。

橘猫在**你自己的电脑上**运行。规划时不调用云端 AI 接口，不会偷偷改你的产品代码，
也不会替你上架发布。

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="橘猫规划面板" width="280">

## 为什么需要它

| 没有橘猫 | 有橘猫 |
|----------|--------|
| 「帮我做个 App」→ AI 自己加功能 | 先用几句普通人的话说明白 |
| 聊着聊着范围越变越大 | 边界和「这版先不做」写清楚 |
| AI 说做完了却对不上 | 有计划，做完还可核对 |
| 每次都要重新讲项目 | 尽量用项目里已有的信息 |

## 安装（v0.4.0-rc.2 Preview）

### macOS 应用（不会终端的人优先）

[**下载 Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)

1. 下载 `JumaoCat-v0.4.0-rc.2-arm64.zip`
2. 解压 → 把 `Jumao Cat.app` 拖进 **「应用程序」**
3. 从 **「应用程序」** 打开（不要从压缩包窗口直接开）

要求：macOS 14+、Apple 芯片（arm64）。已签名并公证。用 App **不必**先装 Node.js。

### 终端（CLI）

```bash
npm install -g jumao@rc
```

安装的是当前 Preview 线（`rc` 标签 → `0.4.0-rc.2`）。

更早的版本（如 v0.3.1）仍在 Releases 里，**只作历史对照**。新用户请从
**v0.4.0-rc.2** 开始，不要再装旧线当入口。

## 第一次用：大约五分钟

1. **打开橘猫**，选一个文件夹  
   - 空文件夹 = 新想法  
   - 已有代码 = 「改这个项目」
2. **用普通话说清楚**  
   - 新项目：做什么、能干什么、先在哪用？  
   - 可选：这版**先不做什么**  
   - 已有项目：这次想改成什么样？
3. **确认**橘猫理解对了。它会在本地整理开发计划。
4. **看计划**：先做什么、要守住什么、哪些先不能动。
5. **交给 AI 编程工具**  
   - App 里点「交给 Codex」（或复制给 Claude / Cursor 的说明）  
   - 在工具里打开**同一个**文件夹，粘贴说明  
6. **让 AI 在该文件夹里实现**。做完后可用橘猫核对完成说明（终端：
   `jumao verify`，只对你信任的项目）。

更细的步骤见 **[开始使用](docs/getting-started.zh-CN.md)**。

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="新项目的普通问题" width="640">

## 从想法到 AI 开发

```text
  你的想法 / 这次改动
         │
         ▼
  橘猫（本地计划 + 边界）
         │
         ▼
  一份你能打开阅读的计划
         │
         ▼
  AI 编程工具（Codex / Claude / Cursor）
         │
         ▼
  代码 + 可选的完成核对
```

对开发者来说：橘猫是 AI Coding Agent 前面的**决策与交付控制层**——范围、禁区、
怎样算完成、要保护什么。真正写代码的仍是 AI 工具；上线、收费、真实用户相关动作
仍由你确认。

机制说明（给想看清原理的人）：  
**[橘猫如何工作](docs/concepts/how-jumao-works.zh-CN.md)**。

## 安全一句话

规划默认在本地、默认只读你的源码。记录写在 `.jumao/`。交给 AI 的主文件通常是
`tasks/jumao-agent-plan.md`。橘猫不收费、不替你发布、不为你调 AI API。

## 给开发者（CLI）

```bash
npm install -g jumao@rc

jumao plan /你的/项目路径
jumao plan /你的/项目路径 --json
jumao plan /你的/项目路径 --force
jumao verify /你的/项目路径
jumao verify /你的/项目路径 --no-run-checks   # 不执行项目测试
```

`jumao verify` 默认可能重跑项目测试，只对你信任的代码使用；静态核对用
`--no-run-checks`。

另有：`interview`、`doctor`、`new`、`inspect`、`check`、`audit`、`pack`、
`status` 等命令。

## 文档

| 给谁 | 文档 |
|------|------|
| 第一次用 | [开始使用](docs/getting-started.zh-CN.md) |
| 产品理解 | [橘猫如何工作](docs/concepts/how-jumao-works.zh-CN.md) |
| 更多模板说明 | [使用指南](docs/guide.zh-CN.md) |
| 本 Preview 变更 | [更新记录](CHANGELOG.md) |
| 参与贡献 | [贡献方式](CONTRIBUTING.zh-CN.md) |

## 许可证

MIT — [LICENSE](LICENSE)。
