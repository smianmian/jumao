# Jumao Cat macOS

Jumao Cat 是本地 macOS 菜单栏应用。它可以选择新项目或已有项目、完成聚焦问答，
并通过 App 内置的 Node.js 和 Jumao CLI 自动运行 Agent Planning Runtime。

Runtime 不调用外部 AI API。扫描和规划默认只读项目源码，规划结果写入项目的
`.jumao/` 和 `tasks/`。

## 准备内置 Runtime

```bash
./scripts/prepare-bundled-runtime.sh --arch current
./scripts/prepare-bundled-runtime.sh --verify-only
```

内置 Runtime 位于 `Resources/BundledRuntime/`，该目录由脚本生成且不提交 Git。
它必须包含独立 Node 可执行文件、当前 Jumao CLI、runtime manifest 和第三方许可证。

## 在 Xcode 打开

打开 [JumaoCat.xcodeproj](JumaoCat.xcodeproj)，选择 `JumaoCat` scheme 后运行，或执行：

```bash
xcodebuild build -scheme JumaoCat
xcodebuild test -scheme JumaoCat
```

应用没有 Dock 图标。点击菜单栏橘猫后可以选择项目、恢复问答草稿、查看最近一次
规划、重新整理，并把 `tasks/jumao-agent-plan.md` 对应的启动指令交给 Codex。

目录访问权限使用 macOS security-scoped bookmark 保存。App 会监听
`.jumao/status.json`，并从 `.jumao/latest-run.json` 恢复真实规划结果。

## 发布边界

正式 Developer ID 签名脚本是 `scripts/sign-release-app.sh`。只有明确进行正式发布时
才能运行；普通本地构建和 Release Candidate 验证不运行该脚本，也不执行 Apple 公证。
