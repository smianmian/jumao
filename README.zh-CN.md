# Jumao 橘猫

[English](README.md)

Jumao Cat 会把一个新产品想法，或已有项目的一次改动，整理成有真实证据、
可以交给 Codex 的开发计划。它在本地做规划，默认不会修改项目源码，也不会替你发布。

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat 项目选择和规划面板" width="280">

## 下载 Jumao Cat

[**下载 Jumao Cat for macOS**](https://github.com/smianmian/jumao/releases/latest)

当前支持：

- macOS 14 或更高版本、Apple 芯片 Mac（arm64）
- 已发布下载包使用 Developer ID 签名并通过 Apple 公证
- App 不需要系统 Node.js、Homebrew、npm 或全局 Jumao
- 也提供 Node CLI，供需要终端流程的人使用

下载 ZIP，解压后把 `Jumao Cat.app` 拖到“应用程序”，再从“应用程序”打开。

## Jumao Cat 的普通使用流程

1. 选择一个新项目文件夹，或已有代码项目。
2. 新项目只回答 3 道普通问题：想做什么、希望它能做哪些事、想先在哪里使用。
3. 已有项目只描述“这次想改成什么样”。Jumao Cat 会读取能看到的项目证据，
   不再让你重复回答它已经知道的事实。
4. 确认 Jumao Cat 理解正确后，App 自动运行本地 Agent Planning Runtime。
5. 查看 8 个小组、44 个专业角色的真实处理结果，包括哪些已完成、已跳过、
   被阻塞或运行失败。
6. 查看生成的、可以交给 Codex 的开发计划。
7. 点击“交给 Codex”，在 Codex 中打开同一个项目文件夹，再粘贴已经复制的指令。

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Jumao Cat 新项目三道普通问题" width="640">

Jumao Cat 会恢复没有填完的问答草稿，也会恢复最近一次规划结果。项目或需求变化后，
可以直接重新整理。

## Agent Planning Runtime 到底是什么

Agent Planning Runtime v1 是一个**本地确定性规则流水线**，不会调用外部 AI API。

44 个 Agent 是分在 8 个小组中的、可以审计的专业检查角色，不是 44 个独立大模型
在并行开发。每个角色都会得到真实运行状态：

- `completed`：找到相关证据并完成分析
- `skipped`：没有找到相关触发条件或项目证据
- `blocked`：缺少必须由人确认的决定或输入
- `failed`：角色处理或产物写入未能完成

结果来自用户回答、只读项目扫描和项目中的真实证据。当前“可能受影响的文件”使用
保守的证据匹配，并不是完整的代码依赖图。

## 文件和安全边界

- 扫描和规划阶段默认只读项目源码。
- 运行记录、manifest、证据和 latest run 状态写入 `.jumao/`。
- 当前主要交接文件是 `tasks/jumao-agent-plan.md`。
- Jumao Cat 不调用外部 AI API，不自动添加业务代码，不发布、不收费，也不替人做发布决定。

## Node CLI

同一个 Planning Runtime 也可以在终端使用：

```bash
npm install -g jumao
jumao plan /你的/项目路径
```

需要机器可读输出或强制重新运行时：

```bash
jumao plan /你的/项目路径 --json
jumao plan /你的/项目路径 --events-jsonl
jumao plan /你的/项目路径 --force
```

原有的 `new`、`interview`、`inspect`、`check`、`audit`、`doctor`、`pack` 和
`status` 命令继续保留。v0.3.1 没有破坏性 CLI 变更。

## 文档

- [使用指南](docs/guide.zh-CN.md)
- [Agent 说明](docs/agents.zh-CN.md)
- [发布检查清单](docs/publish-checklist.zh-CN.md)
- [更新记录](CHANGELOG.md)
- [贡献方式](CONTRIBUTING.zh-CN.md)
