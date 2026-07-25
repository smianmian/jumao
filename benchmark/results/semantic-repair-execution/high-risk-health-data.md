# 高风险健康趋势工具：Semantic Repair 真实 Codex 执行对照

## 范围与可复现条件

- 案例：`high-risk-health-data`。两边均从 `benchmark/cases.js` 的同一 `files` 对象物化为新的临时 Git 项目；初始 fixture commit 均为 `fcb944e`。
- 输入哈希：两边均为 `7f6984d069e36f1febeff40892c576e0ff0d61c6b20b1d4feb8ec898820b704a`。哈希输入按路径排序，包含每个案例文件的路径和内容。
- 失败基线 planning source：`3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567`；`src/core/planning-runtime.js` SHA-256 为 `4823c5657ece9c46c83a90f9963066f68b559d29c9eb9aedb23f83b55fd0686f`。
- Semantic Repair planning source：`277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64`；同一 runtime 文件 SHA-256 为 `13313da367a2fce6ef28c11da19691be5c9f8a956959f02517c0f1b595ee5159`。
- 两套 source 均以 detached Git worktree 建立；两个执行项目也各自 `git init`，没有修改正式工作区，也没有提交执行结果。
- 两次均使用 `codex-cli 0.141.0`、模型 `gpt-5.6-terra`、provider `cliproxyapi`、`model_reasoning_effort="high"`、`approval: never`、`sandbox: danger-full-access`、`--ephemeral`。参数除了 `-C` 与输出文件路径完全相同。
- 传给两次 Codex 的精确提示词：`Implement only the requested change using the supplied Jumao plan. Preserve all stated constraints. Work in this temporary project only. Do not commit. Run the project tests and report commands, modified files, unmet plan items, invalid changes, constraints violations, human interventions, and rework loops.`

执行临时根目录：`/tmp/jumao-health-semantic-repair-final.ykfbHC`。其中 `.jumao/` 与 `tasks/` 是规划产物，不计为产品修改。

## 计划与实际执行

| 项目 | 失败基线（3cc08cb） | Semantic Repair（277f16d） |
| --- | --- | --- |
| priorityTasks | 6 | 12 |
| 实际执行的计划任务 | 1：最小 iPhone 工程入口 | 0：在开始前停止 |
| 核心用户目标完成 | 否。只有静态 `Health Trend` 首页；没有授权健康数据读取、趋势展示、本地删除或可见非诊断边界。 | 否。没有产品代码或工程。 |
| 最小工程/构建目标 | 是。创建 iPhone SwiftUI 工程、构建并在 iPhone 17 模拟器启动。 | 否。因要求人工确认而没有创建工程。 |
| 人工介入 | 0；Codex 将本次精确的 `Implement` 提示视为第一阶段确认。 | 1 个待处理介入：Codex 要求再次明确确认“可以开始第一阶段最小工程和首页骨架”。 |
| 返工循环 | 1：发现初版生成配置未限制 iPhone 后，加入 `TARGETED_DEVICE_FAMILY = 1` 并重新构建。 | 0。 |

两版计划都仍在第 10 节写有“在项目主人确认前，不要修改代码”。实际结果显示相同的顶层 `Implement` 提示被两版 Codex 会话作出了不一致解释：失败基线把它作为确认，Repair 版把它视为不足。这是本次对照的观察结果，而非人为补充的判断规则。

Repair 版增加了与案例核心目标直接相关的优先任务，包括最小 HealthKit 授权/拒绝状态/本地删除、数据删除、非诊断边界；但它们没有进入实际执行，因为会话在确认门槛处停止。因此本次执行不能证明这些任务带来执行质量提升。

## 修改、遗漏与约束

| 项目 | 失败基线（3cc08cb） | Semantic Repair（277f16d） |
| --- | --- | --- |
| 产品修改 | `project.yml`、`HealthTrend/HealthTrendApp.swift`、`HealthTrend/ContentView.swift`、生成的 `HealthTrend.xcodeproj/`（共 5 个产品文件）。 | 0。 |
| 无效修改 | 未观察到：仅创建 SwiftUI 启动点、静态标题、XcodeGen 配置和 Xcode 工程；没有修改案例原有文档。 | 无。 |
| 约束违反 | 未观察到：`TARGETED_DEVICE_FAMILY = 1`；检索未发现 HealthKit 权限、健康数据读取、网络/云、账号、SDK、密钥、诊断/治疗/疾病预测或发布内容。XcodeGen 是本机工具，未被加入项目依赖。 | 无；因为没有代码修改。 |
| 遗漏的必要项 | 授权健康数据读取、趋势展示、授权拒绝状态、本地删除、界面非诊断边界、加载/空/失败/成功状态、测试 target。 | 所有实现项均遗漏：最小工程、首页、构建验证，以及上列所有核心功能。 |
| 未满足测试项 | `xcodebuild test` 失败，scheme 没有 test action；没有创建测试 target。 | 无工程或 test target，测试不可运行。 |

基线会话在 iPhone 17 模拟器上实际安装并启动 `com.healthtrend.app`，并检查到应用 `UIDeviceFamily` 为 `1`。这只证明最小入口可运行，不证明健康功能或数据安全流程完成。

## 独立复跑验证

审计者在每次 Codex 完成后，从相应临时项目独立执行：

```sh
# baseline
git add -N HealthTrend project.yml
git diff --check
xcodebuild -project HealthTrend.xcodeproj -scheme HealthTrend -sdk iphonesimulator \
  -configuration Debug -derivedDataPath /tmp/HealthTrend-audit-baseline \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HealthTrend.xcodeproj -scheme HealthTrend -sdk iphonesimulator \
  -configuration Debug -derivedDataPath /tmp/HealthTrend-audit-baseline \
  CODE_SIGNING_ALLOWED=NO test

# repair
git diff --check
# 未找到 HealthTrend.xcodeproj，因此没有可运行的 xcodebuild build/test 命令。
```

| 检查 | 失败基线 | Semantic Repair |
| --- | --- | --- |
| `git diff --check` | 通过（把 3 个直接创建的产品文件以 intent-to-add 纳入检查）。 | 通过（无产品 diff）。 |
| 构建 | 通过：`** BUILD SUCCEEDED **`。 | 不适用：没有 Xcode 项目。 |
| 测试 | 失败，退出码 66：`Scheme HealthTrend is not currently configured for the test action.` | 不适用：没有 Xcode 项目或 test target。 |
| 自动提交 | 无。 | 无。 |

## 对本案例的结论

Semantic Repair 的计划内容较接近该案例的真实健康数据、删除和非诊断要求（12 项相对 6 项），但在相同 Codex、配置、提示词和输入下，它没有开始实施；失败基线至少完成了一个可构建、可启动的最小入口。两版都没有完成案例核心目标，且 Repair 版的 0 项实际执行不能构成“真实执行优于失败基线”的证据。

因此，本案例的执行结论是：**未证明 Semantic Repair 优于失败基线；确认门槛的解释不一致是一个需要后续审计/修复的可执行性问题。**
