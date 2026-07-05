# 发布清单

这份清单用于把橘猫从本地仓库发布到 GitHub 或 npm。发布动作会影响外部平台，执行前请先人工确认。

## 本地检查

```bash
npm run check
npm pack --dry-run
git status --short
```

必须确认：

- `npm run check` 通过。
- `npm pack --dry-run` 里的文件符合预期。
- `git status --short` 没有未提交改动。
- README 中没有临时占位、旧项目名或不适用内容。
- 示例工作区能通过 `jumao check` 和 `jumao pack`。

## GitHub 发布

建议仓库名：`jumao`

确认后再执行：

```bash
gh repo create smianmian/jumao --public --source=. --remote=origin --push
```

发布后检查：

- GitHub 页面能打开。
- README 默认显示正常。
- `main` 分支包含最新提交。
- 远程地址已经写入 `origin`。

## npm 发布

首版不必须发布 npm。只有当你确认要让别人用 `npx jumao` 或全局安装时，再执行 npm 发布。

发布前确认：

- 包名 `jumao` 可用。
- 版本号符合要发布的版本。
- `npm pack --dry-run` 内容正确。
- 已登录正确的 npm 账号。

确认后再执行：

```bash
npm publish
```

## 不能提前声称的事

- 不能在没有远程仓库前说“已经开源”。
- 不能在没有 npm 发布前说“已经发布 npm”。
- 不能在没有用户确认前创建远程仓库、push 或 npm publish。
