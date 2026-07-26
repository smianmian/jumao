# v0.4 Product Validation Benchmark

运行：

```sh
node benchmark/run.js
```

它会为四个项目案例分别运行不可变的 `v0.3.1` tag 和当前工作区，并写入 `benchmark/results/`：

- `manifest.json`：原始运行清单。
- `priority-tasks.json`：用于比较的优先任务快照。
- `explain-chain.json`：每项任务的角色、证据、发现、保护项和决策影响。
- `comparison-report.md`：跨案例比较与人工复核建议。

v0.3.1 没有原生 priority task 或 decision impact 数据。benchmark 只从其已完成 Agent 的 `tasks` 生成兼容快照，不伪造 v0.4 的契约字段；因此缺少的覆盖率会如实显示为零。
