# v0.4 Semantic Repair Validation

## 冻结范围与结论

本报告验证 `277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64` 的 Semantic Repair；它不是发布结论，也没有合并 `main`、创建正式 tag 或执行 `npm publish`。

**最终结论：FAIL。** 修复后的结构、对抗案例和回归测试均通过，但三组受控的真实 Codex 执行中没有两组显示修复版优于失败基线：Node CLI 平局，SaaS 与健康数据案例均未证明修复版更好。因此不满足预先冻结的 PASS 标准，不得进入 release candidate。

## 固定比较点

| 用途 | Commit |
| --- | --- |
| 原 benchmark 基线 | `ed2b2288d96408c2358de502b37fbcc172f43f47` |
| 失败 runtime checkpoint | `3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567` |
| 失败 Product Validation Audit | `16f0d3fbd05e6a43307698da4eedfda7bc0d5cdf` |
| Semantic Repair | `277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64` |

`v0.3.1` tag、`schemaVersion`、发布文件和 `main` 均未在本轮修改。`CHANGELOG.md` 与 `ROADMAP.md` 是工作区既有的未提交修改，不属于本轮提交范围。

## 修复后的语义与实现位置

`status` 只描述 Agent 是否完成评估：`completed`、`blocked`、`skipped`、`failed`。`completed` 不再表示一定改变计划；`assessmentOutcome` 描述结果：

- `completed + changed_plan`：需要可靠 evidence、独立 finding、任务或保护约束、plan contribution 和 decision impact。
- `completed + no_change`：需要可靠 evidence 和说明现有计划足够的独立 finding；任务、保护约束、contribution 和 impact 必须均为空。
- `blocked`：不产生可执行 priority task，并记录阻断问题。

语义设计见 [V0_4_AGENT_ASSESSMENT_SEMANTICS.md](../../docs/V0_4_AGENT_ASSESSMENT_SEMANTICS.md)。实现位于 `src/core/planning-runtime.js`：`evidenceGateFor()`（619 行）在角色分析前处理证据不足、冲突、双语否定歧义和缺少备份/回滚/验证/人工确认的不可逆工作；适用性与范围在输入规范化及 `analyzeAgent()`（1298 行）中处理；`priorityTaskRecords()`（1678 行）先按同目标、scope 与保护边界合并贡献，保留 `contributingRoles` 与 `merged_task`，且不再有最终六项硬截断。

## 冻结对抗案例：8/8

所有案例的人工期望在运行前已写入对应 `expected.md`；本轮没有按运行结果改案例或评分。完整观察见 [comparison.md](adversarial/comparison.md)。

| 对抗案例 | 修复版观察 | 结果 |
| --- | --- | --- |
| 现有计划正确 | 0 priorityTasks；可记录 `completed + no_change` | 通过 |
| 触发词但证据不足 | 相关账号角色 blocked；0 task | 通过 |
| 角色适用但无风险 | security `completed + no_change`；0 task | 通过 |
| 中英文否定作用域歧义 | blocked；0 task | 通过 |
| 相互冲突的访问约束 | blocked；0 task | 通过 |
| 多角色相似任务 | 合并任务保留多个 contributing roles | 通过 |
| monorepo 局部约束 | 任务带 package path scope | 通过 |
| 不可逆认证/迁移 | blocked，未直接生成执行任务 | 通过 |

## 四个原始案例的内容回归审计

这是对修复后生成计划内容的人工检查，不把 evidence 或 decision-impact 的 100% 结构覆盖率当成内容正确性的证明。重跑产物见各案例目录及 [comparison-report.md](comparison-report.md)。

| 案例 | 修复后的必要内容 | 审计结果 |
| --- | --- | --- |
| SaaS 网页会员目录 | 网页登录入口、匿名/登录/会员状态与权益；同 scope 的数据字段/字典合并 | 计划内容通过；实际 Codex 执行仍未完成 UI 入口和权益，见后文。 |
| 明确负面约束活动报名 | 保留活动报名与草稿；不生成会员、订阅、支付、营销短信、定位或发布 | 通过。 |
| 高风险健康趋势 | HealthKit 最小授权、授权拒绝、本地删除、非诊断边界 | 计划内容通过；实际执行未开始。 |
| Node CLI `--json` | `--json`、原有文本输出兼容验证；没有网页 UI 任务 | 通过。 |

当前四案例的结构量为 148 个 baseline 兼容候选任务对 28 个修复版 priorityTasks（不是旧审计中的 23 个）。重复 3→0，unsupported 7→0。此变化仅证明候选结构发生变化；不能单独证明内容更准确或执行质量提升。

## 真实 Codex 执行对照

三组均在独立临时项目执行，未改正式工作区、未自动提交。每组在两边使用相同物化输入、相同 `codex-cli 0.141.0`、`gpt-5.6-terra`、`high` reasoning、相同提示词和权限；报告记录了不同 runtime source commit 与 `planning-runtime.js` SHA-256，排除同一 runtime 跑两次。

| 案例 | baseline | Semantic Repair | 审计结论 |
| --- | --- | --- | --- |
| [Node CLI](semantic-repair-execution/existing-node-cli-refactor.md) | 完成 `--json` 和文本兼容；2/2 测试通过；3 个文件；0 人工介入/返工 | 相同核心目标与 2/2 测试；2 个文件；0 人工介入/返工 | 平局，不能证明更优。 |
| [SaaS](semantic-repair-execution/saas-web-membership.md) | 部分完成；2/2 测试；3 个文件、1 次返工 | 部分完成；3/3 测试；2 个文件、0 次返工，但隐私政策任务未完成 | 未证明更好；两边均未给出 UI 入口和会员权益，且均有“主人确认”解释冲突。 |
| [高风险健康数据](semantic-repair-execution/high-risk-health-data.md) | 创建可构建、可启动的最小 iPhone 入口；测试 target 缺失；未完成核心健康功能 | 因把计划中的人工确认解释为阻断，0 个产品改动、无工程 | 修复版未证明更好，且确认门槛的可执行语义不一致。 |

因此“至少两组真实执行明显优于失败基线”的 PASS 条件为 **0/2** 达成。

## 验证记录

在生成本报告前，已运行：

    node benchmark/run.js
    node benchmark/run-adversarial.js
    npm test
    npm run check
    git diff --check

结果：四案例产物重写成功；对抗案例 8/8 满足期望；`npm test` 143 passed；`npm run check` passed；`git diff --check` passed。

## 未满足项与下一步

不得发布或进入 release candidate。后续应先以独立的、明确含项目主人确认信号的执行协议，消除“实施提示是否等于主人确认”的歧义；随后重新跑三组隔离 Codex 对照。只有至少两组在核心目标完成、约束合规、遗漏和返工方面明确优于失败基线，才可重新评估结论。不得为了改善数字而修改案例、评分规则或 runtime。
