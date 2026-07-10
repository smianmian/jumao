# Jumao Cat macOS

Jumao Cat 是一个本地 macOS 菜单栏小应用。它只读取：

```text
<workspace>/.jumao/status.json
```

## 在 Xcode 打开

打开 [JumaoCat.xcodeproj](JumaoCat.xcodeproj)，选择 `JumaoCat` scheme 后运行。

应用没有 Dock 图标。点击菜单栏的橘猫，选择一个 Jumao 项目目录，即可看到：

- `cat.state`
- `cat.label`
- `cat.message`
- Agent Board 摘要、最多 3 条关键阻塞和下一步

目录访问权限以 macOS security-scoped bookmark 保存。App 重启后会恢复上次目录，并监听 `.jumao/status.json` 的创建、修改、替换和删除。

没有状态文件时显示 `sleeping`；JSON 无法解析时显示明确的读取错误。应用只读 status 文件，不会写入或修改它。

## 本阶段不做

- 不运行 `jumao doctor` 或 `jumao pack`
- 不复制任务包
- 不打开报告
- 不联网、登录、云同步或调用 AI API
