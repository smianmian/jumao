# SaaS Web Membership：Codex 执行对照

## 范围与可复现条件

- 案例：`saas-web-membership`，两边均由 `benchmark/cases.js` 中同一份文件内容物化到独立临时 Git 仓库。
- 输入指纹相同：`cee635844b03486e19f7c8d177e0d8bd1d3e4ed1a9e079ff1fb972aa484c9485`。
- baseline runtime：`v0.3.1` tag（commit `80cbd3611a6aaff124c4ea84f1682204d9fd168a`）的隔离 worktree。
- current runtime：审计开始时的当前工作树（commit `ed2b2288d96408c2358de502b37fbcc172f43f47`，包含未提交的 `src/core/planning-runtime.js` 改动）。
- 两次均使用本机 `codex-cli 0.141.0`、模型 `gpt-5.6-terra`、provider `cliproxyapi`、`approval: never`、`sandbox: danger-full-access`，各自在独立临时项目中运行，且没有提交。
- 传给两次 Codex 的提示词完全一致：`Implement only the requested change using the supplied Jumao plan. Preserve all stated constraints. Work in this temporary project only. Do not commit. Run the project tests and report commands, modified files, unmet plan items, invalid changes, constraints violations, human interventions, and rework loops.`

执行临时根目录：`/tmp/jumao-saas-execution.PBp0dM`。其中的 `.jumao/` 和 `tasks/` 是规划产物，均未纳入下面的产品代码改动计数。

## 结果

| 项目 | v0.3.1 | v0.4 current |
| --- | --- | --- |
| 目标完成 | 否。Codex 读取计划和边界后遵守“项目主人确认前不要修改代码”，没有实施登录或会员状态。 | 部分完成。新增本地假账号、匿名/登录/会员状态与回归测试；没有可见网页登录入口或会员权益界面。 |
| 产品代码修改文件 | 0 | 2：`src/access.js`、`test/catalog.test.js` |
| 测试 / 构建 | `npm test` 通过：1/1。没有独立 build script。 | `npm test` 通过：3/3。没有独立 build script。 |
| 无效修改 | 未观察到；没有产品代码 diff。 | 未观察到。改动只含 `example.test` 本地 fixture、状态推导和相关测试；没有真实密码、支付、网络服务或发布改动。 |
| 遗漏的必要修改 | 整个请求均未实施。 | 缺少实际网页入口/交互，以及订阅权益如何影响目录或功能的验证；在此极小样例中没有 UI 文件可改，故不能据此证明完整 SaaS 流程。 |
| 人工介入次数 | 0（没有人为 Codex 补写代码）。 | 0（没有人为 Codex 补写代码）。 |
| 返工次数 | 0（无产品代码尝试）。 | 0（观察到一轮代码 diff；无人工返工）。 |
| 约束合规 | 合规：未接支付、未发布、未保存账号/支付信息，匿名浏览未变。 | 合规：`canBrowseCatalog()` 保持 `true`；仅内存 `localAccounts` fixture；未接真实支付、未发布、未保存真实密码或支付信息。 |

## 代码级证据

v0.4 的 `src/access.js` 新增：

- `AccessState`：`anonymous`、`signed-in`、`member`；
- 两个 `.test` 域名的内存 fixture；
- `signInWithEmail()` 和 `getAccessState()`；
- 原有 `canBrowseCatalog()` 仍返回 `true`。

v0.4 的 `test/catalog.test.js` 从空测试改为三项断言：匿名仍可浏览、普通登录和会员状态有别、未知邮箱不创建账号。审计者在执行后独立重跑 `npm test`，得到 3 个通过、0 个失败；`git diff --check` 无输出。

v0.3.1 的 Codex 会话读取了 `tasks/jumao-agent-plan.md`、`.jumao` 任务计划和 `product/release-boundaries.md`，之后没有留下产品代码 diff。审计者独立运行 `npm test`，得到原有 1 个通过、0 个失败；`git diff --check` 无输出。

两次 CLI 执行的最终文字报告都没有写入请求的 `-o` 路径，因此本报告不把未落盘的最终口头总结当作证据；结论仅依据保留的 Codex 命令输出、最终 Git diff 和审计者重跑的测试。v0.4 代码 diff 证明其会话实际执行了修改，v0.3.1 的空 diff 证明其会话未修改产品代码。

## 实际命令

```sh
# 同一案例输入分别物化并初始化为临时 Git 项目后生成计划
node /tmp/jumao-saas-execution.PBp0dM/v0.3.1-source/bin/jumao.js plan /tmp/jumao-saas-execution.PBp0dM/v0.3.1/saas-web-membership --force
node /Users/smianmian/jumao/bin/jumao.js plan /tmp/jumao-saas-execution.PBp0dM/v0.4/saas-web-membership --force

# 对两边各运行一次；提示词见上文，参数除 -C 外相同
codex exec --ephemeral -s danger-full-access -C /tmp/jumao-saas-execution.PBp0dM/v0.3.1/saas-web-membership -o /tmp/jumao-saas-execution.PBp0dM/v0.3.1/codex-final.md '<identical prompt>'
codex exec --ephemeral -s danger-full-access -C /tmp/jumao-saas-execution.PBp0dM/v0.4/saas-web-membership -o /tmp/jumao-saas-execution.PBp0dM/v0.4/codex-final.md '<identical prompt>'

# 审计者执行的相同测试和 diff 检查
(cd /tmp/jumao-saas-execution.PBp0dM/v0.3.1/saas-web-membership && npm test)
(cd /tmp/jumao-saas-execution.PBp0dM/v0.4/saas-web-membership && npm test)
git -C /tmp/jumao-saas-execution.PBp0dM/v0.3.1/saas-web-membership diff --check
git -C /tmp/jumao-saas-execution.PBp0dM/v0.4/saas-web-membership diff --check
```

## 对比结论

这一个案例显示 v0.4 的计划让相同 Codex 从“只读取、未实施”前进到“以本地假数据实现并测试最小状态模型”，且未违反明确负面约束。它不足以证明完整网页登录/订阅体验已完成：v0.4 的执行仍遗漏 UI 入口和权益行为。因此该案例支持“v0.4 更可执行”的有限证据，而不是产品验证通过的证据。
