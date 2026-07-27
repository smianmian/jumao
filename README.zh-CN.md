# Jumao 橘猫

[English](README.md)

**当前公开 Preview：[v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

Jumao Cat（橘猫）会把一个产品想法——或已有项目的一次改动——整理成有真实证据、
可以交给 AI 编程工具（Codex、Claude Code、Cursor 等）的开发计划。

AI 写代码很快，却容易跑出范围、假装完成。橘猫先在**本地**做规划：普通人能懂的
问答、只读项目证据、确定性的专业检查流水线。它**不会**替你写业务源码、不调用
外部 AI API，也不会替你发布。

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat 项目选择和规划面板" width="280">

## 安装（Preview v0.4.0-rc.2）

### 方式 A — Jumao Cat for macOS（多数人推荐）

[**下载 Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)

- macOS 14 或更高，Apple 芯片（arm64）
- Developer ID 签名 + Apple 公证
- 不需要系统 Node.js、Homebrew、npm 或全局安装 Jumao

下载 `JumaoCat-v0.4.0-rc.2-arm64.zip`，解压后把 `Jumao Cat.app` 拖到「应用程序」，
再从「应用程序」打开。

### 方式 B — Node CLI

```bash
npm install -g jumao@rc
jumao plan /你的/项目路径
```

这会安装当前 Preview 线（通过 `rc` dist-tag，对应 `0.4.0-rc.2`）。

> 更早的版本（例如 **v0.3.1**）仍可在 Releases 里查看，仅作历史对照。
> **不推荐**新用户再装旧版作为入口。

## 从想法到 AI 编程工具

1. **说清楚** — 新项目：做什么、能干什么、先在哪用（可选：这版先不做什么）。
   已有项目：这次要改成什么样。
2. **本地规划** — 橘猫跑 Agent Planning Runtime（规则 + 证据，不调模型 API），
   每个专业角色都有真实结果状态。
3. **交出去** — 打开 `tasks/jumao-agent-plan.md`（或在 App 里点「交给 Codex」），
   在编程工具里打开同一项目文件夹并粘贴指令。
4. **核对** — AI 干完应留下完成回执；对信任的项目可用 `jumao verify` 独立核验。

## Jumao Cat 的普通使用流程

1. 选择新项目文件夹，或已有代码项目。
2. 新项目回答 3 道普通问题，外加一道可跳过的「这版先不做什么」。
3. 已有项目只描述「这次想改成什么样」；橘猫读取可见项目证据，不再重复已知事实。
4. 确认理解正确后，App 自动跑本地规划运行时。
5. 查看 8 个小组、44 个专业角色的结果（完成 / 跳过 / 阻塞 / 失败）。
6. 查看生成的、可交给编程工具的开发计划。
7. 点「交给 Codex」（或复制给 Claude Code / Cursor 的指令），在工具里打开同一
   文件夹并粘贴。

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Jumao Cat 新项目三道普通问题" width="640">

未完成的问答草稿和最近一次规划可以恢复；项目或需求变了可以重新整理。

## Agent Planning Runtime 是什么

Agent Planning Runtime v1 是**本地确定性规则流水线**，不调用外部 AI API。

44 个 Agent 是分在 8 个小组里、可审计的专业检查角色，不是 44 个大模型在并行写
代码。每个角色都有真实状态：`completed` / `skipped` / `blocked` / `failed`。

结果来自你的回答、只读扫描和项目里的证据。「可能受影响的文件」是保守匹配，
不是完整依赖图。

## 文件和安全边界

- 扫描和规划默认只读项目源码。
- 运行记录、manifest、证据和 latest run 写在 `.jumao/`。
- 主要交接文件：`tasks/jumao-agent-plan.md`。
- 不调用外部 AI API，不自动加业务代码，不发布、不收费，也不替人做发布决定。

## CLI 补充

```bash
npm install -g jumao@rc

jumao plan /你的/项目路径
jumao plan /你的/项目路径 --json
jumao plan /你的/项目路径 --events-jsonl
jumao plan /你的/项目路径 --force
jumao verify /你的/项目路径
jumao verify /你的/项目路径 --no-run-checks
```

默认 `jumao verify` 会在项目里重跑测试（`npm test` / `xcodebuild test`），用来抓
「回执说测过了其实没有」。**只对你信任的项目做完整核验。** 不执行测试时用
`--no-run-checks`。

`jumao interview` 默认只问聚焦问题（完整问卷加 `--full`）。`jumao doctor` 不带
参数是中文选择题。`new`、`inspect`、`check`、`audit`、`pack`、`status` 等命令
仍然可用。

## 文档

**先看这些**

- [使用指南](docs/guide.zh-CN.md) — 第一次怎么走
- [更新记录](CHANGELOG.md) — 本 Preview 改了什么

**再深入**

- [Agent 说明](docs/agents.zh-CN.md)
- [贡献方式](CONTRIBUTING.zh-CN.md)
- [发布检查清单](docs/publish-checklist.zh-CN.md)

## 许可证

MIT — 见 [LICENSE](LICENSE)。
