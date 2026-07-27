# Planning Runtime 拆分方案

目标：在**不改变** `planWorkspace` 对外行为与 golden 测试结果的前提下，
把 `src/core/planning-runtime.js`（约 2500 行）拆成可独立审阅的模块。

本文件是实现前的边界图与迁移顺序，不是一次大爆炸重构。

## 为什么拆

| 问题 | 影响 |
|------|------|
| 信号 / 库存 / Agent 执行 / 任务合成 / 落盘混在同一文件 | 单文件 diff 难审、冲突多 |
| 与 `inspect.js` 重复的 skip/敏感规则 | 只改一边会行为分叉 |
| 测试只能整文件导入 | 单测成本高，局部回归难 |

## 模块边界图

```
planWorkspace (public façade)
        │
        ├── intake.js          读/规范化 .jumao/intake-answers.json
        ├── inventory.js       工作区文件库存扫描（可与 inspect 共用 scan-policy）
        ├── signals.js         中英信号、否定边界、impact files、scope
        ├── goals.js           explicitGoals / evidenceGate / blockingQuestions
        ├── context.js         buildContext + input fingerprint
        ├── pipeline.js        executePipeline、group 顺序、事件
        ├── agent-executor.js  executeAgent / relevance / analyze / evidence 契约
        ├── task-plan.js       synthesizeTaskPlan / stages / priority tasks / render markdown
        ├── artifacts.js       run 目录、manifest、latest-run、publish task plan
        └── util.js            hash、atomic write、时间、runId
```

`agent-registry.js`、`execution-handoff.js`、`completion-receipt.js`、`status.js`、
`inspect.js` 保持现状；拆分时只**调用**它们，不把它们并入 runtime。

## 建议目录

```
src/core/planning/
  index.js              # re-export planWorkspace + 现有测试依赖的 export
  plan-workspace.js     # 编排 try/catch 与 status 写入
  intake.js
  inventory.js
  signals.js
  goals.js
  context.js
  pipeline.js
  agent-executor.js
  task-plan.js
  artifacts.js
  util.js
src/core/scan-policy.js # 从 inspect + planning 抽出共用常量
src/core/planning-runtime.js  # 过渡期：export * from './planning/index.js'
```

过渡期保留 `planning-runtime.js` 路径，避免 CLI / Mac bundled runtime / 测试
大面积改 import。

## 各模块职责（硬边界）

### `scan-policy.js`（先做，收益最大）

- `skippedDirectories`、`sensitiveNamePattern`、`sensitiveExtensions`、
  `binaryExtensions`、`sourceExtensions`（inventory 侧）
- `inspect.js` 与 planning inventory **共用同一份**，禁止再复制粘贴

### `intake.js`

- `readIntake`、`normalizeIntake`、`normalizeNewAnswers`、
  `normalizeExistingAnswers`、`normalizePlatform`
- 不碰文件系统以外的副作用

### `inventory.js`

- `collectWorkspaceInventory` 及扫描辅助
- 输入：workspacePath；输出：files + kinds + warnings

### `signals.js`

- `signalPatterns` / `signalAgentMap` / `detectSignals` / 否定句切分
- `findImpactFiles`、`scopeForRequest`、`executionBoundaryFor`

### `goals.js`

- `explicitGoalsFor` 与 goal 家族正则
- `evidenceGateFor`、`blockingQuestionsFor`
- 后续若要「从 doneWhen 推导可核验模式」，改这里即可

### `context.js`

- `buildContext`、`inputFingerprint`
- 聚合 intake + inspection + inventory + signals + goals

### `agent-executor.js`

- `executeAgent`、`relevanceForAgent`、`analyzeAgent`、
  `intent/project/roleEvidence*`
- 现有导出：`validateEvidenceQuality`、`validateAgentEvidence`、
  `validateGoalCoverage`、`priorityTaskRecords`（测试直接引用）

### `pipeline.js`

- `executePipeline`、agent/group 计数、planning 事件 shape
- 依赖 `agent-executor`，不写盘

### `task-plan.js`

- `synthesizeTaskPlan`、`renderTaskPlan`、stage/priority/protection 合并
- 调用 `execution-handoff` / `completion-receipt`

### `artifacts.js`

- `writeRunArtifacts`、`writeFailureArtifacts`、`publishTaskPlan`、
  `writeLatestRun`、`buildManifest`、`reusableResult`

### `plan-workspace.js`

- 现有 `planWorkspace` 主体：reuse 短路、status checking/blocked、
  失败回写、返回 `resultFromExecution`

## 迁移顺序（每步保持 `npm test` 全绿）

1. **抽出 `scan-policy.js`**，`inspect` + planning inventory 改 import  
2. **抽出 `util.js` + `intake.js`**，planning-runtime 改为 re-export/调用  
3. **抽出 `inventory.js` + `signals.js` + `goals.js` + `context.js`**  
4. **抽出 `agent-executor.js`**（含测试直接 import 的 export）  
5. **抽出 `pipeline.js` + `task-plan.js` + `artifacts.js`**  
6. **`planning/index.js` 成为真入口**，`planning-runtime.js` 变一行 re-export  
7. 可选：更新 bundled runtime 清单路径（若仍复制整棵 `src/` 则无需改路径）

每一步要求：

- 不改 golden case 期望
- 不改 `plan --json` / `--events-jsonl` 字段名
- 不改 `.jumao/runs/...` 目录布局

## 明确不做的事

- 不在拆分时改 44 Agent 规则语义
- 不顺手引入 TypeScript / 构建步骤
- 不把 Mac `AppState` 拆分绑进同一 PR（单独 PR，避免跨语言大 diff）

## 验收

- `npm test` 227+ 全绿  
- 对同一 fixture 跑 `jumao plan` 两次（`--force`），manifest 与 task plan 结构一致  
- `git diff` 行为层应接近「只搬家、不改算法」

## 预估体量

| 步骤 | 粗估 |
|------|------|
| scan-policy | 小（1 小时级） |
| intake + util | 小 |
| inventory/signals/goals/context | 中 |
| agent-executor + pipeline | 中大 |
| task-plan + artifacts + 入口收口 | 中 |

建议拆成 2–4 个 PR，不要一次合入全部模块。
