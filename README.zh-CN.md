# 你该怎么用 Jumao

Jumao 不是 App，也不是代码生成器。
它是你让 Codex / Claude / Cursor 写代码之前，用来把想法说清楚的小工具。

如果终端提示 `npm: command not found` 或 `command not found: npm`，先安装 Node.js LTS，因为 Jumao 通过 npm 安装。
安装完以后，关闭终端再重新打开。

https://nodejs.org/

## Jumao 内置 Agent 是什么

Jumao 内置了 44 个责任单元 Agent。
你不用雇 44 个人。
这些 Agent 会在你让 Codex 写代码前，帮你检查产品、设计、数据、隐私、上架、收费、发布这些缺口。

想看完整说明：

[查看 44 个内置 Agent 说明](docs/agents.zh-CN.md)

## 1. 安装 Jumao

```bash
npm install -g jumao
jumao --help
```

## 2. 创建一个项目

```bash
mkdir -p ~/jumao-work
cd ~/jumao-work
jumao new "我的 App" --dir ./my-app
jumao interview ./my-app
jumao check ./my-app --strict
jumao audit ./my-app --write
jumao pack ./my-app --target codex
```

## 3. 复制 Codex 任务包

Mac 用户：

```bash
cat ./my-app/tasks/codex-task-pack.md | pbcopy
```

不是 Mac：

```text
打开 ./my-app/tasks/codex-task-pack.md，复制里面全部内容。
```

## 可选：让 Jumao 先帮你做项目体检

如果你准备正式上线、收费、登录、上 App Store，先跑：

```bash
jumao doctor ./my-app --answers ./node_modules/jumao/examples/ai-note-helper/doctor-answers.json --write
jumao pack ./my-app --target codex
```

Jumao 会把体检结果写到 `governance/`，并把硬门禁带进 task pack。

## 4. 在 Codex 客户端里怎么用

- 打开 Codex 客户端。
- 打开你的项目文件夹：`~/jumao-work/my-app`。
- 新开一个对话。
- 粘贴刚才复制的 task pack。
- 再发送这句话：

```text
请先阅读上面的 Jumao task pack。
先总结产品目标、首版范围、风险边界和下一步最小安全任务。
我确认后，你再开始改代码。
不要做 task pack 之外的事情。
```

## 5. 在 Codex CLI 里怎么用

```bash
cd ~/jumao-work/my-app
codex
```

打开后，粘贴刚才复制的 task pack，再粘贴这句话：

```text
请先阅读上面的 Jumao task pack。
先总结产品目标、首版范围、风险边界和下一步最小安全任务。
我确认后，你再开始改代码。
不要做 task pack 之外的事情。
```

## 6. 在 Claude Code 里怎么用

先生成 Claude 任务包：

```bash
cd ~/jumao-work
jumao pack ./my-app --target claude
cat ./my-app/tasks/claude-task-pack.md | pbcopy
```

不是 Mac：

```text
打开 ./my-app/tasks/claude-task-pack.md，复制里面全部内容。
```

- 打开 Claude Code。
- 打开你的项目文件夹：`~/jumao-work/my-app`。
- 粘贴 Claude task pack。
- 再发送这句话：

```text
请先阅读上面的 Claude task pack。
先总结产品目标、首版范围、风险边界和下一步最小安全任务。
我确认后，你再开始改代码。
不要做 task pack 之外的事情。
```

如果你用 Claude Code 的命令行，也可以这样打开：

```bash
cd ~/jumao-work/my-app
claude
```

打开后，粘贴 Claude task pack，再粘贴这句话：

```text
请先阅读上面的 Claude task pack。
先总结产品目标、首版范围、风险边界和下一步最小安全任务。
我确认后，你再开始改代码。
不要做 task pack 之外的事情。
```

## 7. 卸载

```bash
npm uninstall -g jumao
```

## 不想全局安装也可以

只想试一下，用这个：

```bash
npx jumao --help
```

# 橘猫

橘猫是一套面向 AI 编程工具的项目治理 CLI。

它帮你在把想法交给 Codex、Claude 或 Cursor 之前，先把产品目标、
首版边界、页面状态、数据安全、交付规则和完成证据整理成文件。
这样 AI 开始写代码前，先知道该做什么、不能做什么、
哪些动作必须停下来问人。

橘猫不调用模型 API，不需要 API Key，不替你自动写完整 App，
不发布 npm，不 push 远程仓库。

English version: [README.md](README.md)

## 5 分钟跑通

在仓库根目录运行：

```bash
node bin/jumao.js new "AI Note" --dir ./tmp/ai-note
node bin/jumao.js interview ./tmp/ai-note --answers ./examples/ai-note-helper/answers.json
node bin/jumao.js check ./tmp/ai-note --strict
node bin/jumao.js audit ./tmp/ai-note --write
node bin/jumao.js pack ./tmp/ai-note --target codex
```

跑完后，你会得到一个产品工作区：

```text
./tmp/ai-note
```

以及一份可以交给 Codex 的任务包：

```text
./tmp/ai-note/tasks/codex-task-pack.md
```

把这份任务包交给 AI 编程工具时，先让它总结产品目标、
首版范围、风险和下一步最小安全任务，再开始改代码。

## 核心闭环

```text
new -> interview -> check --strict -> audit -> pack --target codex|claude|cursor
```

| 步骤 | 证明什么 |
| --- | --- |
| `new` | 产品工作区已经生成。 |
| `interview` | 用户不用面对空白 Markdown，也能补齐核心产品信息。 |
| `check --strict` | 上下文不再是空模板、占位词或泛泛而谈。 |
| `audit` | 用户能看到缺口、影响和下一步安全 AI 任务。 |
| `pack --target` | Codex、Claude 或 Cursor 能拿到带工具规则的任务包。 |

## 适合谁

- 有 App、网站、SaaS、AI 工具或小产品想法的人。
- 不太会写代码，但会用 Codex、Claude Code、Cursor 这类工具的人。
- 希望 AI 写代码前先理解产品边界的人。
- 希望每轮 AI 工作都留下测试、截图、日志或人工验收的人。

## 解决的问题

AI 编程经常一开始就跑偏，原因通常不是模型不够强，
而是上下文太糊。

- 用户是谁没说清。
- 首版范围太大。
- 不该做的功能没有写下来。
- 页面缺少加载、空状态、错误、成功、权限拒绝。
- 数据收集、保存、删除规则不清楚。
- AI 没有证据就说完成。
- AI 过早碰发布、生产数据、付费或远程仓库。

橘猫把这些风险整理成文件、检查、诊断报告和任务包。

## 命令

```bash
jumao init [dir]
jumao new <product-name> --dir [dir]
jumao check [dir]
jumao check [dir] --strict
jumao audit [dir]
jumao audit [dir] --write
jumao doctor [dir] --answers answers.json
jumao doctor [dir] --answers answers.json --write
jumao interview [dir]
jumao interview [dir] --answers answers.json
jumao interview [dir] --answers answers.json --force
jumao pack [dir]
jumao pack [dir] --target codex
jumao pack [dir] --target claude
jumao pack [dir] --target cursor
```

没有全局安装时，在本仓库里用 `node bin/jumao.js ...` 即可。

| 命令 | 做什么 |
| --- | --- |
| `init` | 在目录里放入橘猫文档、模板和可填写的产品骨架。 |
| `new` | 创建一个产品工作区。 |
| `check` | 检查必需文件是否存在。 |
| `check --strict` | 门禁：拦住占位词、泛话、空结构和核心产品信息缺口。 |
| `audit` | 诊断缺口，说明影响，并给出下一步安全 AI 任务。 |
| `audit --write` | 把诊断写入 `tasks/audit-report.md`。 |
| `doctor --answers` | 用生活化答案做项目体检，触发内置 Agent Review Board。 |
| `doctor --write` | 把体检报告、Agent 缺口和 Codex 硬门禁写入 `governance/`。 |
| `interview` | 通过问答补齐四个核心产品文件。 |
| `interview --answers` | 用 JSON 非交互生成核心文件；加 `--force` 会覆盖已填写文件。 |
| `pack` | 生成旧版兼容的 `jumao-task-pack.md`。 |
| `pack --target` | strict 门禁通过后，生成 Codex、Claude 或 Cursor 任务包。 |

## 生成的工作区

`jumao new "AI Note"` 会生成：

```text
AGENTS.md
CLAUDE.md
README.zh-CN.md
README.md
product/
  product-brief.zh-CN.md
  product-brief.md
  scope-gate.zh-CN.md
  scope-gate.md
  screen-states.zh-CN.md
  screen-states.md
  data-safety.zh-CN.md
  data-safety.md
proof/
  release-proof.zh-CN.md
  release-proof.md
```

`pack --target codex|claude|cursor` 还会在 `tasks/` 下生成
对应工具的任务包。

## 和 AI 编程工具配合

### Codex

```bash
node bin/jumao.js pack ./tmp/ai-note --target codex
```

Codex 任务包会提醒它先读 `AGENTS.md`，只改请求范围内的文件，
完成前跑测试，并汇报 changed / not changed / test result / remaining gaps。

### Claude

```bash
node bin/jumao.js pack ./tmp/ai-note --target claude
```

Claude 任务包会提醒它先读 `CLAUDE.md`，保持实现范围克制，
大改前先说明假设。

### Cursor

```bash
node bin/jumao.js pack ./tmp/ai-note --target cursor
```

Cursor 任务包会提醒它保持小改动，优先沿用现有项目结构，
不要主动新建架构。

## 完整示例

看 [examples/ai-note-helper](examples/ai-note-helper)。
它是一个已经填好的“AI 笔记助手”工作区。

```bash
node bin/jumao.js check examples/ai-note-helper --strict
node bin/jumao.js audit examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper --target codex
```

Quickstart 使用的示例答案在
[examples/ai-note-helper/answers.json](examples/ai-note-helper/answers.json)。

## 发布前检查

发布前先跑本地检查，并且确认任何外部动作都有人明确同意：

```bash
node bin/jumao.js --help
npm test
npm run check
npm pack --dry-run
npm publish --dry-run
git status --short
```

创建 GitHub 仓库、push 分支、发布 npm、创建 git tag 都是外部发布动作，
需要人工确认后再做。

## 项目文件

- [CHANGELOG.md](CHANGELOG.md)：版本记录。
- [ROADMAP.md](ROADMAP.md)：下一步小范围计划。
- [CONTRIBUTING.md](CONTRIBUTING.md)：贡献规则。
- [SECURITY.md](SECURITY.md)：安全报告方式。
- [docs/guide.zh-CN.md](docs/guide.zh-CN.md)：更完整的使用指南。
- [docs/prompts.zh-CN.md](docs/prompts.zh-CN.md)：可以直接复制的 AI 提示词。
- [docs/publish-checklist.zh-CN.md](docs/publish-checklist.zh-CN.md)：发布清单。

## 常见问题

### 橘猫会调用 OpenAI、Claude 或其他模型吗？

不会。橘猫只读写本地文件，不调用模型 API，不读取 API Key，
不产生模型费用。

### 我不会代码也能用吗？

可以。橘猫的目标就是帮你先把产品讲清楚，
再交给 AI 编程工具继续做。

### 它能直接生成完整 App 吗？

不能。橘猫负责整理产品上下文、边界、任务交接和完成证据。
真正实现仍然需要 AI 编程工具或开发者继续完成。

### 可以商用吗？

可以。橘猫使用 MIT 协议。

## 开源协议

MIT
