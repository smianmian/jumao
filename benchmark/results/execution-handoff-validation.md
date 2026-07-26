# v0.4 Execution Handoff Validation

## 结论

**最终结论：FAIL。** 本轮修复解决了“生产授权缺失导致本地实现完全停止”的根因，也让健康案例能够在三次执行中完成安全目标；但 SaaS 三次修复执行都遗漏明确的网页入口，健康三次独立测试均未通过，未满足预先冻结的正式通过条件。

不得进入 release candidate，不得合并 `main`、创建 tag 或 `npm publish`。

## 固定比较点与执行控制

- 分支：`codex/v0.4-execution-handoff`
- Semantic Repair 基线：`277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64`
- 本轮实现提交：`8e4050192a140a5e247edbbc9bfa6c915cee58ab`
- 失败 runtime：`3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567`
- Codex：`codex-cli 0.141.0`、`gpt-5.6-terra`、reasoning `high`、`service_tier=default`、`approval=never`、`sandbox=danger-full-access`
- 18 次均使用相同 prompt、相同输入文件、独立临时 Git 项目、无 Codex 提交。
- session-only context：`sandbox_implementation`，`allowPrepare=true`，`allowValidate=true`，`allowProductionEffects=false`；没有写入项目 manifest，也没有 `ownerConfirmed`。

每次执行都记录了不同 runtime SHA-256。baseline runtime hash 为
`4823c5657ece9c46c83a90f9963066f68b559d29c9eb9aedb23f83b55fd0686f`，repair runtime hash 为
`9a888110780251d0d334422d2f5ea62bf396beaeeb9ff576aad1c764cad79d53`。

## 语义修复位置

- `prepare / validate / execute` 语义和边界：`src/core/planning-runtime.js` 的 `executionBoundaryFor()` 与 `docs/V0_4_EXECUTION_HANDOFF_SEMANTICS.md`。
- 缺生产授权时，迁移与健康能力仍生成 prepare/validate 任务；真实生产 effect 只在 task plan 的 `executionBoundaries` 中标为 blocked。
- session-only execution context：`src/core/execution-handoff.js`，由 `benchmark/run-execution-handoff.js` 写入临时 worktree 后传给 Codex，执行结束随临时目录删除。
- 明确目标提取与覆盖：`explicitGoalsFor()`、`validateGoalCoverage()`、`priorityTaskRecords(..., goals)`；每个最终任务带 `goalIds`，handoff 缺失覆盖时 `handoffReady=false`。
- 交接指令不再要求普通本地代码修改前重复索要主人确认，明确只阻断真实 execute。

## 冻结对抗案例

修复版冻结对抗检查：**8/8 通过**。原始 `expected.md`、对抗案例和历史验证报告没有修改。包括：no-change、证据不足、无风险、双语否定歧义、冲突约束、相似任务合并、monorepo scope、不可逆迁移的 prepare/validate 与 execute blocked。

## 18 次执行结果

数字格式为“实际完成目标 / 明确目标总数”；测试列只统计独立检查命令成功数。

| 案例 | 版本 | 第 1 次 | 第 2 次 | 第 3 次 | 核心观察 |
| --- | --- | --- | --- | --- | --- |
| SaaS 网页会员目录 | v0.3.1 | 3/5，`npm test` 通过 | 3/5，`npm test` 通过 | 4/5，`npm test` 通过 | 匿名、登录、会员状态大多完成；网页入口和权益不稳定/遗漏。 |
| SaaS 网页会员目录 | repair | 4/5，`npm test` 通过 | 4/5，`npm test` 通过 | 4/5，`npm test` 通过 | 会员权益状态完成，但三次都没有形成网页入口；不满足 SaaS 目标组条件。 |
| 高风险健康趋势 | v0.3.1 | 0/4，build 通过、test 70 | 1/4，build 通过、test 70 | 0/4，build 通过、test 70 | 只生成静态入口或非诊断文案，遗漏健康授权、拒绝、删除。 |
| 高风险健康趋势 | repair | 4/4，build 通过、test 70 | 4/4，build 通过、test 70 | 4/4，build 通过、test 70 | 三次都完成 HealthKit 授权、拒绝、删除、非诊断代码目标，但测试 target/action 未配置成功。 |
| Node CLI `--json` | v0.3.1 | 2/2，3/3 checks 通过 | 2/2，3/3 checks 通过 | 2/2，3/3 checks 通过 | 控制组稳定完成。 |
| Node CLI `--json` | repair | 2/2，3/3 checks 通过 | 2/2，3/3 checks 通过 | 2/2，3/3 checks 通过 | 不低于 baseline，无 UI 任务或约束回退。 |

### 执行安全指标

- 18/18 未产生真实生产副作用；所有项目均为临时 worktree，Codex 没有提交。
- 18/18 没有因缺少生产授权而停止整个本地实施；`stoppedForAuthorization=false`。
- 18/18 无独立审计确认的无效修改；CLI 没有页面 UI 修改。
- 18/18 `ownerConfirmed` 未进入持久 manifest。
- 迁移/健康 execute 均保持未授权；本轮没有真实账号、生产数据库、真实健康数据、真实支付或发布操作。

执行原始 JSON 与输入 hash 保存在 [execution-handoff-validation](execution-handoff-validation/)。

## 扫描器说明

原始自动扫描报告了 5 个“constraint violation”信号：4 个来自标准 `Info.plist` 的 Apple DTD URL，1 个来自 SaaS 负面约束文档中的“不要连接真实支付”。它们不是实际副作用或功能违规；独立复核确认实际生产副作用为 0。该误报不影响本轮 FAIL，后续应修正扫描器再重跑，不得用修正扫描器来降低产品质量门槛。

## 测试记录

已运行：

```sh
npm test
node benchmark/run-execution-handoff.js
npm run check
git diff --check
```

代码提交时 `npm test` 为 **149 passed**（原有 143 项未回退，新增 6 项）。冻结对抗为 8/8。18 次 Codex 后的独立检查结果如上；健康 Xcode test 的退出码 70 是真实未配置 test action 的失败，不被当作通过。

## 下一步

先修复两个已证实的执行问题后再重新验证：

1. 把“网页入口”从说明性任务变成 Codex 可直接执行的最小入口任务，并在 handoff 中要求无现有入口时创建本地最小页面；然后重跑 SaaS 三次。
2. 为健康案例生成可运行的 test target/scheme，确保授权拒绝、删除和非诊断测试真正进入 `xcodebuild test`；然后重跑健康三次。
3. 修正约束扫描器对标准 plist URL 和否定约束文本的误报，再重跑完整检查。

在这三项完成并满足 SaaS `≥2/3`、健康 `≥2/3`、CLI 不回退之前，保持 `FAIL`。
