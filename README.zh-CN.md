# 橘猫

橘猫是给不太会写代码的人用的产品项目夹。

如果你有一个 App、网站或小工具的想法，先别急着让 AI 写代码。
橘猫会带你把几件事写清楚：给谁用，第一版做什么，不做什么，
页面出错怎么办，会碰哪些数据，怎么证明真的做完。

它本身不调用模型，也不碰你的 API Key。填好后，你会得到一份任务包，
可以交给 Codex、Claude Code、Cursor、Gemini CLI 或任何你信任的 AI 编程工具。

English version: [README.md](README.md)

## 3 分钟上手

```bash
git clone <your-fork-or-this-repo> jumao
cd jumao
npm install

node bin/jumao.js new "AI 旅行助手" --dir ./work/ai-travel-helper
node bin/jumao.js check ./work/ai-travel-helper
node bin/jumao.js pack ./work/ai-travel-helper
```

然后把 `./work/ai-travel-helper/jumao-task-pack.md` 丢给你的 AI 编程工具，开场可以这样说：

```text
请先读这份橘猫 AI 任务包，不要急着写代码。
先告诉我你理解的产品目标、首版边界、缺口和下一步最小安全动作。
```

## 橘猫适合谁

- 你有一个 App、网站、SaaS、AI 工具或小产品想法。
- 你不会代码，或者只会一点点，但想让 AI 真正把东西做出来。
- 你怕 AI 一上来乱写、乱扩需求、乱动生产环境。
- 你希望每一步都有测试、截图、日志或人工验收，不想只听 AI 说“差不多好了”。

## 它解决什么

很多 AI 编程项目开头就容易跑偏：想法太散，边界太模糊，AI 不知道哪些能碰、哪些不能碰。

- 这个产品到底给谁用。
- 首版只做什么，不做什么。
- 哪些数据可以收集，哪些不能碰。
- 每个页面的空状态、失败状态、权限状态是什么。
- 什么时候才算真的完成。
- 哪些动作会影响真实用户、账单、审核、上线或生产数据。

橘猫把这些问题拆成一组普通人能填写的文件，再整理成 AI 能读懂的任务包。

## 命令

```bash
jumao init [dir]
jumao new <product-name> --dir [dir]
jumao check [dir]
jumao check [dir] --strict
jumao audit [dir]
jumao audit [dir] --write
jumao interview [dir]
jumao interview [dir] --answers answers.json
jumao pack [dir]
```

没有全局安装时，也可以直接用：

```bash
node bin/jumao.js new "我的产品" --dir ./work/my-product
```

| 命令 | 做什么 |
| --- | --- |
| `init` | 在一个目录里放入橘猫文档、模板、产品骨架。 |
| `new` | 为一个产品生成独立工作区。 |
| `check` | 检查关键文件是否齐全。 |
| `check --strict` | 门禁：拦住占位、泛话和核心结构缺口。 |
| `audit` | 诊断缺口、说明影响，并给出下一步安全 AI 任务。 |
| `audit --write` | 把诊断写入 `tasks/audit-report.md`。 |
| `interview` | 通过问答补齐核心产品文件。 |
| `interview --answers` | 用 `answers.json` 非交互生成；加 `--force` 会覆盖已有核心文件。 |
| `pack` | 打包成可以交给 AI 编程工具的 `jumao-task-pack.md`。 |

## 生成出来长什么样

`jumao new "AI 旅行助手"` 会生成：

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

`jumao pack` 会生成一个 AI 任务包，里面会合并产品简报、首版边界、
页面状态、数据安全和完成证据。AI 编程工具读完后，就不容易一上来写偏。

## 推荐工作流

1. 用 `jumao new` 生成产品工作区。
2. 先填 `product/product-brief.zh-CN.md`，把想法说清楚。
3. 再填 `product/scope-gate.zh-CN.md`，写清楚首版做什么、不做什么。
4. 填 `screen-states`，避免只做顺利路径。
5. 填 `data-safety`，说明收什么数据、放哪里、怎么删。
6. 用 `jumao check` 检查文件是否齐。
7. 用 `jumao pack` 生成任务包。
8. 把任务包交给 Codex、Claude Code、Cursor 或其他 AI 编程工具。
9. 每轮完成后，把测试、截图、日志或人工验收写进 `proof/release-proof.zh-CN.md`。

## 和 Codex / Claude / Cursor 怎么配合

### Codex

把 `jumao-task-pack.md` 贴给 Codex，然后说：

```text
先不要改代码。请根据橘猫任务包总结目标、缺口、风险和下一步计划。
只有当我确认后，才开始实现。
```

### Claude Code

仓库里有 [CLAUDE.md](CLAUDE.md)。把产品工作区交给 Claude Code 后，让它先读 `AGENTS.md` 和 `product/` 下的文件。

### Cursor

把 `AGENTS.md` 的规则放进项目规则，把 `jumao-task-pack.md` 放进上下文。每次让 Cursor 做事前，先问它“这次改动对应哪个首版目标”。

更多可直接复制的提示词见 [AI 提示词](docs/prompts.zh-CN.md)。

## 完整示例

看 [examples/ai-note-helper](examples/ai-note-helper)。这是一个填好的“AI 笔记助手”示例，可以直接运行：

```bash
node bin/jumao.js check examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper
```

示例任务包会长这样：

```text
# 橘猫 AI 任务包

## product/product-brief.zh-CN.md

首版只证明一件事：用户输入一段混乱笔记后，
能得到一个可复制的标题、一段摘要和三条下一步行动。

## product/scope-gate.zh-CN.md

首版明确不做：登录、付费、团队协作、云同步、自动发布。
涉及真实用户、生产数据、付费、上线或外部账号的动作，必须人工确认。
```

完整输出在 [examples/ai-note-helper/jumao-task-pack.md](examples/ai-note-helper/jumao-task-pack.md)。

## 重要原则

- 先让 AI 问清楚，再让 AI 写代码。
- 没有证据，不要说完成。
- 不懂技术也可以做产品，但涉及真实用户、钱和上线的事不能让 AI 猜。
- 任何会影响用户、付费、上线、审核、生产数据的动作，都要人工确认。

## 维护者发布前检查

发布到 GitHub 或 npm 前，先在本地跑：

```bash
npm run check
npm pack --dry-run
git status --short
```

只有在工作区干净、检查通过、包内容符合预期后，再创建远程仓库并 push。
创建 GitHub 仓库、push、发布 npm 都是外部动作，建议先人工确认。

更完整的发布步骤见 [发布清单](docs/publish-checklist.zh-CN.md)。
想参与改进请先看 [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)，
安全问题见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md)，版本变化见
[CHANGELOG.md](CHANGELOG.md)。

## 常见问题

### 橘猫会调用 OpenAI、Claude 或其他模型吗？

不会。橘猫只生成本地文件，不调用模型、不读取 API Key、不产生模型费用。

### 我不会代码也能用吗？

可以。橘猫的第一目标就是帮你把想法讲清楚，再交给 AI 编程工具继续做。

### 它能直接生成一个完整 App 吗？

不能，也不应该承诺。橘猫负责把需求、边界、状态、数据、安全和证据整理清楚，让 AI 编程工具少走弯路。

### 为什么一直强调“证据”？

因为 AI 很容易说“已经完成”，但真实项目需要测试、截图、日志、审核状态或人工验收来证明。

### 可以商用吗？

可以。橘猫使用 MIT 协议。

## 开源协议

MIT
