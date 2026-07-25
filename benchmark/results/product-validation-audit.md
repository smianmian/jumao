# Product Validation Audit — v0.4

## 审计范围与冻结点

- Benchmark 基线提交：`ed2b2288d96408c2358de502b37fbcc172f43f47`，只包含 `benchmark/`；没有合并 main、创建 tag 或执行 `npm publish`。
- v0.3.1 使用不可变 annotated tag `v0.3.1`（tag object `80cbd3611a6aaff124c4ea84f1682204d9fd168a`，解析后的 commit `93d44fc0503124c88a571a97bbcad86c7514d96e`）。其 `planning-runtime.js` blob 是 `9a6a205c8377e2daba9d4166caa5588380dd8bd9`。
- v0.4 使用审计开始时的当前工作树：基准 commit 是上述 `ed2b228`，但 runtime 改动仍未提交；实际执行的 `planning-runtime.js` blob 是 `09f48ed077c3cfe42ea6eb3d28bde9404710a4e0`。这是可识别、但尚非由 commit 单独复现的冻结点。
- 本审计没有修改 `src/core/planning-runtime.js`、`schemaVersion`、`v0.3.1` tag 或发布文件。

## 方法审计

### 1. 两边是否使用相同输入、项目证据和配置？

**原始案例输入是相同的，运行时产生的 evidence 不是相同对象。** `benchmark/run.js` 对每个版本都以同一个 `benchmarkCase.files` 对象调用 `materializeCase()`；两个临时 workspace 从相同文件文本开始，CLI 参数均为 `plan <workspace> --force`，没有版本专属配置。四个原始 manifest 的 `inputFingerprint` 在版本间也完全相同：

| 案例 | 两边相同的 inputFingerprint |
| --- | --- |
| SaaS 网页会员目录 | `cee635844b03486e19f7c8d177e0d8bd1d3e4ed1a9e079ff1fb972aa484c9485` |
| 明确负面约束 | `984a8d2b9ae535fc4778250c1b891caf0099dc48a3511b70cd4247eb62ee693c` |
| 高风险健康数据 | `3c39241b0aac5745158c94e740ccdd9d4c97b4cd286166282cec320f0443c0ca` |
| Node CLI 改造 | `8591f06ee185267a7fd4560f5b99345e5103b3c953e1a3351597e2bccf8d7ef0` |

但 v0.4 会从相同输入额外推导 `platforms` 和 `negativeSignals`，并记录 role evidence；这正是被测能力，不能称为“相同 evidence”。公平表述是：**原始需求、工程文件和启动参数相同；派生 evidence 与计划产物按版本不同。**

### 2. 是否误跑同一 runtime 两次？

否。runner 对 baseline 执行 `git worktree add --detach <tmp>/v0.3.1-source v0.3.1`，并调用该目录的 `bin/jumao.js`；current 调用 `/Users/smianmian/jumao/bin/jumao.js`。上述两个 runtime blob hash 不同。manifest 也佐证 v0.4 多出 `input.platforms` 与 `input.negativeSignals`，而 v0.3.1 没有这些字段。

限制：current runtime 未单独提交。因此基准可以通过记录 blob hash 重现，却不能只检出 `ed2b228` 就复现；这本身阻止本轮成为 release candidate 依据。

### 3. 是否存在偏向 v0.4 的案例或评分逻辑？

存在，且影响结论：

- 四个原始案例在 v0.4 实现之后编写，使用了 `login`、`membership`、`local fake data`、`health`、平台和否定词等 v0.4 明确识别的表达；它们不是独立盲测样本。
- baseline 没有原生 `priorityTasks`。runner 将 baseline **所有 completed Agent 的 `tasks`** 作为兼容候选集，而 v0.4 使用最多六项的原生 `priorityTasks`。这不是相同层级的对象；148 对 23 是候选工作量信号，不是同一选择器的输出量。
- `evidenceCoverage` 的 current 侧在 `independentFinding` 存在时直接算可追溯；而 v0.4 completed contract 本来就强制 independent finding。故 100% 大部分是结构保证，不能证明 finding 的内容正确。
- `decisionImpactCoverage` 对 current 同样是 completed contract 强制字段；baseline 从未有该字段，0% 是格式缺失而非行为失败。
- 当前任务选择器按角色优先级排序并在 `priorityTaskRecords()` 末尾硬截 `.slice(0, 6)`；所以任务变少可以由截断产生，不能自动解释成正确删噪。

结论：原始 benchmark 仅能说明**结构产物满足 v0.4 contract**，不能独立证明任务内容、裁剪正确性或 Codex 执行质量。

### 4. 148 → 23 的归因

这 125 项减少不能从现有 artifact 被精确逐项归因；下表是可审计的下限，不把“未看到”美化为正确删减。

| 类别 | 数量 | 证据与解释 |
| --- | ---: | --- |
| 正确去重 | 3 | 原报告的四个 baseline 内精确重复分别为 1、1、0、1；v0.4 为 0。 |
| 正确合并 | 0 | 23 项里没有一个 `contributingRoles` 多于一个，也没有 `merged_task` impact；不能声称发生了成功合并。 |
| 无证据任务删除 | 7 | baseline 报告的 unsupported 全部来自健康案例；这只是 runner 的兼容判定，不代表其余 118 项都受支持。 |
| 因角色优先级/六项上限裁剪 | 115 | `125 - 3 - 0 - 7`。这是未被内容审计证明正确的剩余选择性裁剪，且受 `.slice(0, 6)` 影响。 |
| 可能遗漏的有效任务 | 7 | 非互斥风险项：SaaS 回归验证（1）、活动报名本身（1）、HealthKit/非诊断/删除（3）、CLI 的 `--json` 与文本兼容验证（2）。 |

### 5. unsupported 7 → 0 的原因

不能证明七项获得了更可靠的内容证据。高风险案例的七项 baseline 候选没有进入 current 的六项 priorityTasks；current 剩余任务因 completed contract 都带 finding/evidence，所以分母改变且结构上全部合格。它主要是**任务被选择器移出 priority 集合**，而不是逐项补强证据后保留。

### 6. 100% coverage 到底证明什么？

- **结构保证：**所有 23 项都来自 status `completed` 的 contribution。`validateAgentEvidence()` 要求 `independentFinding`、任务或约束、有效 `decisionImpact` 和 `planContribution`；因此 evidence/impact 100% 预期会出现。
- **内容正确性：**结构检查不验证 finding 是否与请求相符，也不验证 task 是否足以完成目标。负面约束案例仍得到“会员”任务；Node CLI 案例的五项 priorityTasks 没有 `--json` 或保留文本输出；健康案例没有 HealthKit、非诊断或删除任务。这是 100% 字段覆盖但内容不足的直接反例。

### 7. `completed` 与 `assessed_no_change` 语义

当前没有 `assessed_no_change` status：`validAgentStatuses` 只有 `completed`、`skipped`、`blocked`、`failed`。更重要的是，completed 路径先调用 `analyzeAgent()`，再由 `decisionImpactFor()` 用首项任务机械生成 `created_task` 或 `changed_priority`；contract 要求 task/constraint 和 impact，失败则改为 skipped。

事实结论：

- “角色完成检查且认为无需改计划”**不能**以成功记录；它要么生成任务/约束/impact，要么不是 completed。
- 存在为了满足 completed 契约而强行产出任务、保护项或优先级变化的风险。对抗案例 `assessed-no-change`、`applicable-no-risk` 都产生了 5–6 项 priorityTasks；所有 impact 也均非空。
- 这不是对 runtime 的修复建议，而是当前语义审计事实。

## 23 项 priorityTask 人工质量审计

图例：`I` = intake，`D` = deterministic signal，`P` = 项目文件/只读检查。每一行的完整 evidence、finding、impact 仍保存在对应案例的 `v0.4/priority-tasks.json` 与 `explain-chain.json`；此表保留来源和人工结论。

### SaaS 网页会员目录（4 正确、2 可疑、0 错误）

| v0.3.1 原任务 | v0.4 对应任务 | 状态 / roles | evidence；independentFinding | 删除或合并理由；关键约束遗漏 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 整理并验证账号能力 | 匿名、登录、会员状态；本地假账号且保留匿名 | retained/refined；backend | I,D(login),P；三种状态且不扩成生产后端 | 正确替换泛化账号任务；无 | 正确 |
| 整理官网/隐私页面 | 确认网页、匿名与登录后最小界面 | retained/refined；website_frontend | I,D(web),P；Web 不混入 Apple | 具体化网页范围；缺 QA priority | 正确 |
| 列数据字段清单 | 最小账号/会员字段和假数据标记 | retained/refined；database | I,D(login),P；不需生产数据库 | 与下一行的数据清单高度重叠 | 可疑 |
| 只记录实际数据/权限 | 不启用无证据服务 | retained；security_privacy | I,D(login),P(boundary)；未授权服务不启用 | 保留秘密和支付边界；无 | 正确 |
| 个人信息/数据字典 | 最小数据清单、用途/保存/删除 | retained/refined；data_governance_dictionary | I,D(login),P；不能默认多收集资料 | 本应与字段任务合并，实际无 merged impact | 可疑 |
| 注销/删除记录 | 真实账号注销与删除是进入生产条件 | retained/refined；privacy_request_ops | I,D(login)；本地假账号不声称生产能力 | 适合作后续阶段条件；无 | 正确 |

### 明确负面约束活动报名页（3 正确、0 可疑、3 错误）

| v0.3.1 原任务 | v0.4 对应任务 | 状态 / roles | evidence；independentFinding | 删除或合并理由；关键约束遗漏 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 整理账号能力 | 匿名、登录、**会员**状态 | retained but expanded；backend | I,D(login),P；登录与会员三状态 | 输入没有会员或订阅；凭空扩大 | 错误 |
| 整理官网 | 网页/访客/登录后最小界面 | retained/refined；website_frontend | I,D(web),P；Web 范围 | 报名草稿入口未被明确列出 | 正确 |
| 数据字段清单 | 账号与**会员**字段 | retained but expanded；database | I,D(login),P；本地假数据 | 会员字段无证据 | 错误 |
| 安全边界 | 实际数据/权限、未授权服务关闭 | retained；security_privacy | I,D(login),P(boundary)；不默认启用 | 正确保留支付/位置/消息禁令 | 正确 |
| 数据字典 | 账号与**会员**数据清单 | retained but expanded；data_governance_dictionary | I,D(login),P；资料最小化 | 会员数据无证据；报名草稿的数据边界反而缺失 | 错误 |
| 注销流程 | 生产登录前的注销/删除条件 | retained/refined；privacy_request_ops | I,D(login),P；不声称生产能力 | 真实账号的后续条件合理 | 正确 |

### 高风险健康趋势工具（3 正确、3 可疑、0 错误）

| v0.3.1 原任务 | v0.4 对应任务 | 状态 / roles | evidence；independentFinding | 删除或合并理由；关键约束遗漏 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 安全/权限边界 | 仅记录实际数据和权限 | retained；security_privacy | I,D(health),P(iOS)；未授权服务不启用 | 缺 HealthKit 最小授权和本地删除任务 | 正确 |
| 产品最小流程 | 整理一次用户过程 | retained；product_manager | I,P；用户给出趋势/删除能力 | 太泛，未对应健康流程 | 可疑 |
| 页面状态 | 列入口和四种状态 | retained；ui_ux | I,P；不得只做顺利路径 | 太泛，缺趋势/授权拒绝状态 | 可疑 |
| 最小验证 | 主流程/失败/回归验证 | retained；qa_testing | I,P；无现有测试 | 正确但未覆盖健康数据授权 | 正确 |
| 字体适配 | 整理字体适配 | retained；accessibility | I,D(iPhone),P；辅助功能用户 | 适用但没有任务特定证据或优先性 | 可疑 |
| iOS 权限说明 | 整理 iOS 权限说明 | retained；ios_engineer | I,D(iPhone),P；iPhone 能力 | 应明确 HealthKit、非诊断和删除，不只是泛 iOS | 正确 |

### Node CLI 报表改造（2 正确、2 可疑、1 错误）

| v0.3.1 原任务 | v0.4 对应任务 | 状态 / roles | evidence；independentFinding | 删除或合并理由；关键约束遗漏 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 安全边界 | 仅记录实际数据和权限 | retained；security_privacy | I,P(Node CLI)；未授权服务不启用 | 不直接支持 `--json`；属通用防护 | 可疑 |
| 产品最小流程 | 整理一次用户过程 | retained；product_manager | I,P；不扩大相邻模块 | 未指向 `bin/report.js`、JSON 格式或文本兼容 | 可疑 |
| 页面状态 | 列 UI 四种状态 | retained；ui_ux | I,P(Node CLI)；通用页面 finding | CLI 没有页面；明显不适用 | 错误 |
| 测试 | 主流程/失败/既有能力验证 | retained；qa_testing | I,P(test file)；现有测试必须运行 | 是保留文本输出的必要验证 | 正确 |
| CI/构建 | 保留构建/测试命令和记录结果 | retained；cicd_build | I,P(package.json)；无证据新增证书 | 合理，但 `--json` 与文本输出仍未成为 priorityTask | 正确 |

**合计：正确 12、可疑 7、错误 4。** 另有上述 7 项可能遗漏的有效任务；这些遗漏不能由“字段齐全”抵消。

## 对抗性验证（运行前写期望）

八个案例及其运行前期望在 `benchmark/adversarial-cases.js` 和每案例 `expected.md` 中保存；运行器没有修改既有四案例或评分规则。观察结果见 `benchmark/results/adversarial/comparison.md`。

| 类别 | 预期 | v0.4 观察 | 结果 |
| --- | --- | --- | --- |
| 已确认无需变更 | assessed_no_change，0 task | 5 tasks，0 blocked | 未满足 |
| 触发但证据不足 | 不生成账号类任务 | 6 tasks，backend/database/privacy 均 completed | 未满足 |
| 适用但无风险 | 成功“无风险”评估 | 6 tasks，security 为 high impact | 未满足 |
| 双语否定歧义 | 阻塞澄清 | 6 tasks，0 blocked | 未满足 |
| 证据冲突 | 阻塞匿名/强制登录冲突 | 6 tasks，0 blocked | 未满足 |
| 相似角色任务 | 一个合并的本地数据边界任务 | 6 tasks，未见 merged impact | 未满足 |
| monorepo 局部约束 | 标出 package 范围 | 5 tasks，未标 package scope | 未满足 |
| 不可逆认证/迁移 | 备份、回滚、授权和人工确认 | 6 通用 tasks，0 blocked | 未满足 |

结果是 0/8 达到人工期望。这些不是发布阻断项被测试“遗漏”的假设，而是已执行的反例。

## 真实 Codex 隔离执行

两组执行使用相同 case 输入、相同提示词、独立临时 Git 项目、不提交产品代码；详细命令、输入/runtime hash 和限制见各自报告。

| 案例 | v0.3.1 | v0.4 | 对比 |
| --- | --- | --- | --- |
| SaaS 网页会员目录 | 未改产品代码；`npm test` 1/1；0 文件、0 返工、0 人工介入 | 部分完成；`npm test` 3/3；2 文件、0 无效修改/返工/人工介入；保持本地假数据、匿名浏览、无支付/发布 | v0.4 有限更可执行，但遗漏网页登录入口和权益行为，不能证明目标完整完成。 |
| Node CLI `--json` | 完成；`npm test` 2/2；2 文件；0 无效/遗漏/返工/人工介入 | 同样完成；`npm test` 2/2；2 文件；0 无效/遗漏/返工/人工介入 | 平局；没有 v0.4 执行质量优势。 |

执行报告：[SaaS](/Users/smianmian/jumao/benchmark/results/execution/saas-web-membership-codex-execution.md) 与 [Node CLI](/Users/smianmian/jumao/benchmark/results/execution/existing-node-cli-refactor-codex-execution.md)。

## 最终结论：FAIL

`FAIL`：任务数下降已经得到结构验证，但没有证明执行质量整体提高；23 项中有 4 项错误、7 项可疑，健康和 CLI 关键目标存在遗漏，8 个对抗性案例全部失败，且 completed 不能表达 assessed_no_change。当前不得进入 v0.4 release candidate。

下一步应先在不新增 Contract 的前提下决定 completed/assessed_no_change 的产品语义，并修复证据冲突、否定作用域、monorepo scope、不可逆操作与 priority cap 的内容问题；随后以预先冻结的独立案例重跑本审计和至少两组真实执行。
