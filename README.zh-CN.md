# Jumao 橘猫

[English](README.md)

Jumao 帮你把模糊的 App 想法或一次改动，整理成 AI 编程工具可以先读懂的项目资料、边界和下一步。它不会替你自动完成整个 App；它先让需求、范围、页面状态和数据安全变得清楚。

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat 主面板：扫描空文件夹后显示新项目入口" width="280">

## 下载 Jumao Cat

[**下载 Jumao Cat for macOS**](https://github.com/smianmian/jumao/releases/latest)

> **早期预览：** Jumao Cat v0.3.0 目前重点是项目扫描、需求梳理和 AI 开发前的边界整理。完整的一键规划、Agent 执行和开发任务生成仍在持续完善。

当前支持：

- macOS 14 或更高版本
- Apple 芯片 Mac（arm64）
- 已完成 Developer ID 签名和 Apple 公证
- App 用户不需要安装 Node.js、Homebrew、npm 或全局 Jumao

安装很简单：下载 ZIP，解压后把 `Jumao Cat.app` 拖到“应用程序”，再从“应用程序”打开它。

## 新项目怎么用

1. 在 Jumao Cat 中选择一个空文件夹，或准备开始规划的文件夹。
2. 点击“开始规划新项目”。
3. 依次回答：要做什么、核心功能、当前目标和运行平台。

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Jumao Cat 新项目四题问答完成页" width="640">

v0.3.0 会把这轮新项目回答保存为 `.jumao/intake-answers.json`。这是首轮结构化梳理，不会自动生成 Xcode、网站或 App 源码工程，也不会自动完成完整项目规划。

## 已有项目怎么用

1. 选择一个已有代码项目。
2. Jumao Cat 会先做只读扫描，识别可见的平台、语言、构建线索、源代码和测试线索。
3. 点击“开始梳理这次改动”，再回答：这次要改什么、当前阻塞什么、哪些已有功能不能破坏。

已有项目问答会携带这次只读扫描结果，避免重复问已能确认的信息。扫描和首轮问答不会修改你的源代码；任何后续写入或开发动作都需要你明确决定。

## v0.3.0 当前能力边界

- 完成新项目与已有项目的首轮梳理，并保存结构化问答结果。
- 对已有项目进行只读 `inspect` 扫描。
- 恢复未完成的问答草稿。
- 提供内置 Jumao CLI 与 Node.js 运行时，App 不依赖系统开发环境。
- 不会直接自动生成完整 App，不会替你发布，也不会代替你做产品、合规或发布决定。

当你需要完整的项目资料和任务包时，可以使用后面的 CLI 高级流程。CLI 中的 `jumao new` 创建的是**项目规划工作区**：其中包含规划文档和模板，不是 Xcode、网站或 App 源码工程。

## Agent 小组：当前到底做了什么

Jumao 当前**注册了 8 个 Agent 小组、44 个 Agent 定义**。它们覆盖：方向与主体、产品与设计、技术与开发、数据与隐私、合规与健康声明、上架与平台资质、收费与运营、发布与事故。

这些是规则和检查视角，不是 44 个已经自动执行开发任务的机器人。

- 已注册：代码中定义了 Agent、小组、触发条件、建议与限制规则。
- 匹配到：CLI 的 `doctor --write` 会根据项目主人提供的答案匹配可能需要参与的 Agent，并写入报告、规则和状态摘要。
- 已产生输出：只有写入的治理报告、规则和状态文件才是实际产物。
- 尚未发生：Agent 不会自行写代码、调用外部服务、完成审核或宣布项目可发布。

完整清单和每个规则的含义见 [Agent 说明](docs/agents.zh-CN.md)。

## 开发者和终端用户：CLI 高级用法

以下命令必须由项目主人在**系统终端**中运行。不要把交互式 `jumao interview` 命令交给 Codex、Claude 或 Cursor 代为执行；问题应由真正了解项目的人亲自回答。

```bash
npm install -g jumao

mkdir -p ~/jumao-work
cd ~/jumao-work
jumao new "我的 App" --dir ./my-app
jumao interview ./my-app
jumao check ./my-app --strict
jumao audit ./my-app --write
jumao pack ./my-app --target codex
```

这里的 `./my-app` 是你自己的规划工作区目录。完成完整 CLI 问答后，Jumao 会生成或更新这些真实规划资料：

- `product/product-brief.zh-CN.md`
- `product/scope-gate.zh-CN.md`
- `product/screen-states.zh-CN.md`
- `product/data-safety.zh-CN.md`
- `proof/release-proof.zh-CN.md`
- `tasks/codex-task-pack.md`（运行 `pack --target codex` 后）

### 把规划交给 Codex

推荐方式是在 Codex 客户端直接打开你的实际项目文件夹，并告诉 Codex：

```text
请先读取项目中的：
- AGENTS.md
- product/
- proof/
- tasks/codex-task-pack.md

先总结目标、范围、风险和下一步最小任务。
我确认前不要修改代码。
```

只有确实需要跨工具复制时，才可以在终端运行：

```bash
cat ./my-app/tasks/codex-task-pack.md | pbcopy
```

它只把文件内容复制到剪贴板，执行后不会显示内容；这不是主要交接方式。

`doctor-answers.json` 中的示例回答仅用于本仓库测试，绝不能作为真实项目的答案输入。

## 技术文档与贡献

- [使用指南](docs/guide.zh-CN.md)
- [Agent 说明](docs/agents.zh-CN.md)
- [发布检查清单](docs/publish-checklist.zh-CN.md)
- [更新记录](CHANGELOG.md)
- [贡献方式](CONTRIBUTING.md)
- [English README](README.md)
