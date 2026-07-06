# 完成证据：AI 笔记助手示例

## 本轮改了什么

- 补齐一个可以直接看的橘猫示例。
- 明确首版只做笔记输入、AI 整理、结果展示、复制和本地历史。
- 明确登录、付费、团队协作、云同步和自动发布都不属于首版。

## 没有改什么

- 没有构建真实 App。
- 没有接入真实 AI API。
- 没有保存或发送真实用户数据。
- 没有发布、上线或提交审核。

## 验证证据

| 证据 | 文件或命令 | 结果 |
| --- | --- | --- |
| 结构检查 | `node bin/jumao.js check examples/ai-note-helper` | 通过 |
| 任务包生成 | `node bin/jumao.js pack examples/ai-note-helper` | 已生成 `examples/ai-note-helper/jumao-task-pack.md` |
| 人工验收 | 读取 `product/` 下四份材料 | 应能看清目标、边界、页面状态和数据安全 |

## 还不能说完成的事

- 不能说 AI 笔记助手已经开发完成。
- 不能说已经接入 AI 服务。
- 不能说已经上线。

## 下一步

- 跑 `jumao check` 和 `jumao pack`。
- 把生成的 `jumao-task-pack.md` 交给 AI 编程工具，让它先总结目标、缺口和下一步安全动作。
