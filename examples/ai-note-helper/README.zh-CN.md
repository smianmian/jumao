# AI 笔记助手

这是一个填好的橘猫示例。你可以看到，一个很小的 App 想法怎么被整理成
产品简报、首版边界、页面状态、数据说明和任务包。

运行示例检查和目标任务包：

```bash
node bin/jumao.js check examples/ai-note-helper --strict
node bin/jumao.js audit examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper --target codex
```

示例目标：用户输入一段混乱想法后，得到一个标题、
一段摘要和三条下一步行动。

`answers.json` 会被根目录 README 的 Quickstart 用来通过 `jumao interview`
填充新工作区。
