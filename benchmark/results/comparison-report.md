# v0.4 Product Validation Comparison

基线使用不可变的 `v0.3.1` Git tag；current 使用当前工作区。每次运行都保存原始 manifest、标准化 priorityTasks 和 explain chain。

说明：v0.3.1 不含原生 `priorityTasks`、独立发现或 decision impact。为公平保留其工作量信号，报告从已完成 Agent 的 `tasks` 生成兼容 priorityTasks；缺少的契约字段不会被补造。

“evidence coverage”表示任务有任务级直接信号、文件证据或独立发现；“unsupported task”是其反面。

| Case | Version | Tasks | Duplicates | Unsupported | Evidence | Decision impact | Protected constraints |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| SaaS 网页会员目录 | v0.3.1 | 36 | 1 | 0 | 100% | 0% | 20 |
| SaaS 网页会员目录 | v0.4 | 8 | 0 | 0 | 100% | 100% | 16 |
| 明确负面约束的活动报名页 | v0.3.1 | 50 | 1 | 0 | 100% | 0% | 20 |
| 明确负面约束的活动报名页 | v0.4 | 6 | 0 | 0 | 100% | 100% | 12 |
| 高风险健康趋势工具 | v0.3.1 | 36 | 0 | 7 | 81% | 0% | 20 |
| 高风险健康趋势工具 | v0.4 | 12 | 0 | 0 | 100% | 100% | 15 |
| 已有 Node CLI 报表改造 | v0.3.1 | 26 | 1 | 0 | 100% | 0% | 18 |
| 已有 Node CLI 报表改造 | v0.4 | 2 | 0 | 0 | 100% | 100% | 8 |

合计：任务 148 → 28；unsupported 7 → 0；evidence 95% → 100%；decision impact 0% → 100%。

## SaaS 网页会员目录（SaaS 项目）

- 任务数变化：36 → 8（-28）
- duplicate task 数变化：1 → 0（-1）
- unsupported task 数变化：0 → 0（0）
- evidence coverage：100% → 100%
- decision impact coverage：0% → 100%
- protected constraint 数量：20 → 16
- 人工修改建议：
  - 确认会员权限、匿名浏览和本地假支付状态符合产品负责人预期。
  - 优先交给 Codex 执行 v0.4 的 8 项优先任务；baseline 有 36 项候选任务需要人工筛选。

## 明确负面约束的活动报名页（明确负面约束项目）

- 任务数变化：50 → 6（-44）
- duplicate task 数变化：1 → 0（-1）
- unsupported task 数变化：0 → 0（0）
- evidence coverage：100% → 100%
- decision impact coverage：0% → 100%
- protected constraint 数量：20 → 12
- 人工修改建议：
  - 确认计划没有把活动报名扩展成真实支付、营销短信、上线或位置收集。
  - 优先交给 Codex 执行 v0.4 的 6 项优先任务；baseline 有 50 项候选任务需要人工筛选。

## 高风险健康趋势工具（高风险数据项目）

- 任务数变化：36 → 12（-24）
- duplicate task 数变化：0 → 0（0）
- unsupported task 数变化：7 → 0（-7）
- evidence coverage：81% → 100%
- decision impact coverage：0% → 100%
- protected constraint 数量：20 → 15
- 人工修改建议：
  - 确认 HealthKit 授权、数据删除方式和“非诊断”文案需由负责人和合规人员复核。
  - 优先交给 Codex 执行 v0.4 的 12 项优先任务；baseline 有 36 项候选任务需要人工筛选。

## 已有 Node CLI 报表改造（已有代码库改造项目）

- 任务数变化：26 → 2（-24）
- duplicate task 数变化：1 → 0（-1）
- unsupported task 数变化：0 → 0（0）
- evidence coverage：100% → 100%
- decision impact coverage：0% → 100%
- protected constraint 数量：18 → 8
- 人工修改建议：
  - 确认 --json 的字段、错误输出和原有人类可读文本输出都与现有 CLI 使用者兼容。
  - 优先交给 Codex 执行 v0.4 的 2 项优先任务；baseline 有 26 项候选任务需要人工筛选。

## 结论

本报告只验证产物结构和候选任务差异；任务数量、evidence coverage 与 decision impact coverage 不能单独证明内容正确或 Codex 执行质量。产品结论必须以独立审计、冻结对抗案例和真实执行对照给出。
