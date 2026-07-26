import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { responsibilityAgents, agentGroups } from '../src/core/agent-registry.js';
import { sandboxExecutionContext } from '../src/core/execution-handoff.js';
import {
  planWorkspace,
  priorityTaskRecords,
  validateAgentEvidence,
  validateEvidenceQuality,
  validateGoalCoverage
} from '../src/core/planning-runtime.js';

const repoRoot = path.resolve(new URL('..', import.meta.url).pathname);
const cli = path.join(repoRoot, 'bin', 'jumao.js');
const agentOutputKeys = [
  'agentId', 'roleId', 'groupId', 'status', 'summary', 'triggerReasons', 'triggerReason',
  'negativeSignals', 'scope', 'intentEvidence', 'projectEvidence', 'roleEvidence', 'evidence',
  'evidenceQuality', 'findings', 'independentFinding', 'decisions', 'protections',
  'protectedConstraint', 'tasks', 'assessmentOutcome', 'generatedTask', 'decisionImpact', 'changedPlanDecision',
  'affectedTaskIds', 'impactType', 'unusedEvidence', 'blockingQuestions', 'planContribution',
  'incompleteEvidence', 'skippedReason', 'error'
];

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-plan-test-'));
}

function write(root, relativePath, content = '') {
  const output = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content, 'utf8');
}

function mkdir(root, relativePath) {
  fs.mkdirSync(path.join(root, relativePath), { recursive: true });
}

function writeIntake(root, mode, answers) {
  write(root, '.jumao/intake-answers.json', `${JSON.stringify({
    schemaVersion: 1,
    mode,
    answers,
    updatedAt: new Date().toISOString()
  }, null, 2)}\n`);
}

function newIntake(root, overrides = {}) {
  writeIntake(root, 'new_project', {
    idea: '一个记录心情的小工具',
    features: '记录一次心情并查看今天的记录',
    platform: 'iPhone',
    ...overrides
  });
}

function existingIntake(root, requestedChange) {
  writeIntake(root, 'existing_project', { requestedChange });
}

function readJSON(root, relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), 'utf8'));
}

function readText(root, relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function latest(root) {
  return readJSON(root, '.jumao/latest-run.json');
}

function manifest(root) {
  const run = latest(root);
  return readJSON(root, path.posix.join(run.runPath, 'manifest.json'));
}

test('declared non-goals become protections and suppress matching signals', () => {
  const root = workspace();
  writeIntake(root, 'new_project', {
    idea: '一个记录心情的小工具',
    features: '记录一次心情并查看今天的记录',
    platform: 'iPhone',
    mustNotInclude: '登录、收费'
  });
  const planned = planWorkspace(root);
  assert.equal(planned.ok, true);
  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  assert.ok(taskPlan.protections.some((item) => item.includes('这一版不做：登录、收费')));
  assert.ok(taskPlan.codexInstructions.some((item) => item.includes('不要实现这些能力')));
  assert.ok(taskPlan.priorityTasks.every((task) => !/登录|收费/.test(task.task)));
});

test('existing-project completion check flows into test checks', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module', scripts: { test: 'node --test' } }));
  write(root, 'src/index.js', 'export const f = () => 1;\n');
  writeIntake(root, 'existing_project', {
    requestedChange: '加一个导出按钮',
    completionCheck: '点导出后能生成文件、不再报错'
  });
  const planned = planWorkspace(root);
  assert.equal(planned.ok, true);
  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  assert.ok(taskPlan.testChecks.some((item) => item.includes('按用户自己定的完成标准验证：点导出后能生成文件、不再报错')));
});

function agentOutput(root, agentId) {
  const run = latest(root);
  return readJSON(root, path.posix.join(run.runPath, 'agents', `${agentId}.json`));
}

function runCLI(root, ...args) {
  return spawnSync(process.execPath, [cli, 'plan', root, ...args], { encoding: 'utf8' });
}

function existingWebMembershipProject(root, requestedChange) {
  write(root, 'package.json', JSON.stringify({
    name: 'local-catalog-demo',
    private: true,
    type: 'module',
    scripts: { test: 'node --test' }
  }));
  write(root, 'src/catalog.js', 'export function listProducts() { return [{ id: "tea" }]; }\n');
  write(root, 'src/access.js', [
    'export function canBrowseCatalog() { return true; }',
    'export function requiresAccount() { return false; }',
    ''
  ].join('\n'));
  write(root, 'test/catalog.test.js', [
    'import assert from "node:assert/strict";',
    'import test from "node:test";',
    'import { canBrowseCatalog } from "../src/access.js";',
    'test("anonymous visitors keep catalog access", () => assert.equal(canBrowseCatalog(), true));',
    ''
  ].join('\n'));
  write(root, '.github/workflows/ci.yml', 'name: CI\njobs:\n  test:\n    runs-on: ubuntu-latest\n');
  write(root, 'product/release-boundaries.md', [
    '# Boundaries',
    '',
    '- Must keep anonymous catalog browsing available.',
    '- Do not connect a real payment provider in the first change.',
    '- Do not store passwords or payment details in this repository.',
    ''
  ].join('\n'));
  existingIntake(root, requestedChange);
}

test('evidence quality accepts user, project, manifest, and deterministic rule evidence', () => {
  const quality = validateEvidenceQuality([
    { source: 'intake.answers.requestedChange', detail: '用户明确要求增加登录。' },
    { source: 'inspect.project.platforms', detail: '只读扫描识别到 Web 平台。' },
    { source: 'manifest.input.platforms', detail: '本次运行 manifest 记录平台为 Web。' },
    { source: 'derived:login', detail: '确定性规则从正向表达识别出登录需求。' }
  ]);

  assert.equal(quality.valid, true);
  assert.equal(quality.invalidReasons.length, 0);
  assert.equal(quality.validEvidence.length, 4);
});

test('evidence quality rejects unsupported generic advice as evidence', () => {
  const quality = validateEvidenceQuality([
    { source: 'opinion:generic', detail: '建议继续优化体验。' }
  ]);

  assert.equal(quality.valid, false);
  assert.ok(quality.invalidReasons.some((reason) => /不支持的 evidence 来源/.test(reason)));
});

test('triggered role without an independent finding cannot satisfy the completed contract', () => {
  const validation = validateAgentEvidence({
    roleId: 'backend_engineer',
    triggerReason: 'signal:login',
    evidence: [{ source: 'derived:login', detail: '确定性规则识别出登录需求。' }],
    independentFinding: null,
    protectedConstraint: null,
    generatedTask: '定义登录状态验证流程。',
    decisionImpact: {
      changedPlanDecision: '将登录任务加入优先任务池。',
      affectedTaskIds: ['task-login'],
      impactType: 'created_task'
    },
    planContribution: { agentIds: ['backend_engineer'] }
  });

  assert.equal(validation.valid, false);
  assert.ok(validation.issues.includes('缺少 independentFinding'));
});

test('duplicate independent findings produce only one priority contribution task', () => {
  const contributions = [
    {
      agentIds: ['backend_engineer'],
      sections: ['firstStage'],
      tasks: ['定义匿名和已登录状态。'],
      evidence: [{ source: 'derived:login', detail: '登录需求规则证据。' }],
      triggerReasons: ['signal:login'],
      triggerReason: 'signal:login',
      independentFinding: '登录状态需要区分匿名和已登录。',
      protectedConstraint: '保留匿名浏览。'
    },
    {
      agentIds: ['database_engineer'],
      sections: ['firstStage'],
      tasks: ['列出匿名和已登录状态字段。'],
      evidence: [{ source: 'derived:login', detail: '登录需求规则证据。' }],
      triggerReasons: ['signal:login'],
      triggerReason: 'signal:login',
      independentFinding: '登录状态需要区分匿名和已登录。',
      protectedConstraint: null
    }
  ];

  const records = priorityTaskRecords(contributions, ['firstStage']);
  assert.equal(records.length, 1);
  assert.deepEqual(records[0].contributingRoles, ['backend_engineer', 'database_engineer']);
  assert.equal(records[0].contributionImpacts[1].impactType, 'merged_task');
  assert.equal(records[0].contributionImpacts[1].lowContribution, true);
});

test('a protected constraint can satisfy the contract without a generated task', () => {
  const validation = validateAgentEvidence({
    roleId: 'security_privacy',
    triggerReason: 'signal:login',
    evidence: [{ source: 'inspect.project.platforms', detail: '只读扫描识别到 Web 平台。' }],
    independentFinding: '登录规划涉及账号数据边界。',
    protectedConstraint: '不得把真实密码写入仓库。',
    generatedTask: null,
    decisionImpact: {
      changedPlanDecision: '将密码保护约束加入计划边界。',
      affectedTaskIds: [],
      impactType: 'protected_constraint'
    },
    planContribution: { agentIds: ['security_privacy'], protections: ['不得把真实密码写入仓库。'] }
  });

  assert.equal(validation.valid, true);
});

test('evidence with no task, constraint, or priority decision is orphaned and incomplete', () => {
  const validation = validateAgentEvidence({
    roleId: 'analytics_growth',
    triggerReason: 'signal:analytics',
    evidence: [{ source: 'derived:analytics', detail: '确定性规则识别出统计需求。' }],
    independentFinding: '统计需求目前不会改变第一阶段计划。',
    protectedConstraint: null,
    generatedTask: null,
    decisionImpact: null,
    planContribution: { agentIds: ['analytics_growth'] }
  });

  assert.equal(validation.valid, false);
  assert.equal(validation.unusedEvidence, false);
  assert.ok(validation.issues.includes('no_change 不得生成任务、约束、影响或贡献'));
});

test('a completed no-change assessment needs evidence and a finding but no task or decision impact', () => {
  const validation = validateAgentEvidence({
    roleId: 'security_privacy',
    triggerReason: 'signal:sensitive',
    evidence: [{ source: 'file:src/export.js', detail: '导出工具只处理公开示例名称。' }],
    independentFinding: '已检查当前本地导出范围，没有账号、网络或敏感数据风险，现有计划足够。',
    assessmentOutcome: 'no_change',
    protectedConstraint: null,
    generatedTask: null,
    decisionImpact: null,
    planContribution: null
  });

  assert.equal(validation.valid, true);
  assert.equal(validation.unusedEvidence, false);
});

test('no-change completed Agents do not manufacture tasks or priority impacts', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'stable-cli', type: 'module', bin: { stable: 'bin/stable.js' } }));
  write(root, 'bin/stable.js', '#!/usr/bin/env node\nconsole.log("stable");\n');
  existingIntake(root, '复核现有 stable 命令计划；已确认目标、约束和测试都正确，本次不需要任何代码或计划变化。');

  planWorkspace(root);

  const founder = agentOutput(root, 'founder_decision');
  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  assert.equal(founder.status, 'completed');
  assert.equal(founder.assessmentOutcome, 'no_change');
  assert.equal(founder.generatedTask, null);
  assert.equal(founder.decisionImpact, null);
  assert.equal(taskPlan.priorityTasks.length, 0);
});

test('insufficient future login language blocks account roles without generating tasks', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'notes-cli', type: 'module', bin: { notes: 'bin/notes.js' } }));
  write(root, 'bin/notes.js', '#!/usr/bin/env node\nconsole.log("notes");\n');
  existingIntake(root, '修正文案；以后可能考虑 login，但当前不做账号、数据库或任何登录流程。');

  planWorkspace(root);

  const backend = agentOutput(root, 'backend_engineer');
  assert.equal(backend.status, 'blocked');
  assert.equal(backend.generatedTask, null);
  assert.equal(backend.planContribution, null);
});

test('an applicable role with no risk completes with no_change and no fabricated high impact', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'local-exporter', type: 'module' }));
  write(root, 'src/export.js', 'export const exportNames = (names) => names.join("\\n");\n');
  existingIntake(root, '审核本地导出工具的安全边界：只处理公开示例名称，没有账号、权限、网络或敏感数据；不需要改动。');

  planWorkspace(root);

  const security = agentOutput(root, 'security_privacy');
  assert.equal(security.status, 'completed');
  assert.equal(security.assessmentOutcome, 'no_change');
  assert.equal(security.decisionImpact, null);
});

test('Node CLI changes skip webpage UI work and retain the CLI goal', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'report-cli', type: 'module', bin: { report: 'bin/report.js' } }));
  write(root, 'bin/report.js', '#!/usr/bin/env node\nconsole.log("items: 0");\n');
  write(root, 'test/report.test.js', 'import test from "node:test";\ntest("report", () => {});\n');
  existingIntake(root, '给现有 report 命令增加 --json 输出，并保留现有文本输出；不要改造成网页、云服务或账号系统。');

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  assert.equal(agentOutput(root, 'ui_ux').status, 'skipped');
  assert.ok(taskPlan.priorityTasks.some((task) => /--json/.test(task.task)));
  assert.ok(taskPlan.priorityTasks.some((task) => /文本输出/.test(task.task)));
});

test('evidence gate blocks conflicting access constraints before any priority task is created', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'catalog', type: 'module' }));
  write(root, 'src/access.js', 'export const canBrowse = () => true;\n');
  write(root, 'product/boundaries.md', '# 边界\n\n- 必须保留匿名浏览。\n');
  existingIntake(root, '所有访问都必须登录，禁止匿名浏览。');

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  assert.equal(agentOutput(root, 'backend_engineer').status, 'blocked');
  assert.equal(taskPlan.priorityTasks.length, 0);
  assert.ok(taskPlan.blockingQuestions.some((item) => /冲突/.test(item)));
});

test('health planning keeps HealthKit, refusal, deletion, and non-diagnostic boundaries', () => {
  const root = workspace();
  newIntake(root, {
    idea: '一个查看健康趋势的 iPhone 工具，不提供诊断或治疗。',
    features: '读取用户授权的 HealthKit 健康数据并展示趋势；展示授权拒绝状态，用户可以删除本地数据，不预测疾病。',
    platform: 'iPhone'
  });

  planWorkspace(root);

  const tasks = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json')).priorityTasks.map((item) => item.task).join('\n');
  assert.match(tasks, /HealthKit/);
  assert.match(tasks, /授权拒绝/);
  assert.match(tasks, /删除本地健康趋势数据/);
  assert.match(tasks, /非诊断/);
});

test('signup planning keeps the draft goal without inventing membership', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'event-signup', type: 'module' }));
  write(root, 'src/signup.js', 'export const submitDraft = () => ({ state: "draft" });\n');
  existingIntake(root, '给现有网页活动页增加邮箱登录后的报名草稿，保留访客查看活动；不要接真实支付，不发送短信或邮件，不收集定位，也不要发布。');

  planWorkspace(root);

  const tasks = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json')).priorityTasks.map((item) => item.task).join('\n');
  assert.match(tasks, /活动报名草稿/);
  assert.doesNotMatch(tasks, /会员|订阅/);
});

test('monorepo priority tasks retain the requested package scope', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'workspace', private: true, workspaces: ['packages/*'] }));
  write(root, 'packages/mobile/product-boundaries.md', '# Mobile\n\n- 不得云同步。\n');
  write(root, 'packages/admin/src/report.js', 'export const report = () => "admin";\n');
  write(root, 'packages/admin/test/report.test.js', 'import test from "node:test";\ntest("report", () => {});\n');
  existingIntake(root, '只修改 packages/admin 的 report 输出，保留文本格式。');

  planWorkspace(root);

  const tasks = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json')).priorityTasks;
  assert.ok(tasks.length > 0);
  assert.ok(tasks.every((task) => task.scope.paths.includes('packages/admin/**')));
  assert.doesNotMatch(readText(root, 'tasks/jumao-agent-plan.md'), /不得云同步/);
});

test('irreversible work keeps prepare and validate tasks while blocking execute', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'migration-tool', type: 'module' }));
  write(root, 'src/migrate.js', 'export const migrate = () => "dry-run";\n');
  existingIntake(root, '实现认证切换和生产数据迁移，准备备份、迁移脚本、回滚和测试；不要执行真实生产迁移。');

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  const tasks = taskPlan.priorityTasks.map((item) => item.task).join('\n');
  assert.match(tasks, /备份/);
  assert.match(tasks, /迁移脚本/);
  assert.match(tasks, /回滚/);
  assert.match(tasks, /测试/);
  assert.ok(taskPlan.executionBoundaries.some((item) => item.phase === 'execute' && item.status === 'blocked'));
  assert.doesNotMatch(tasks, /立即执行生产迁移/);
});

test('health preparation is not blocked by missing production authorization', () => {
  const root = workspace();
  newIntake(root, {
    idea: '一个查看健康趋势的 iPhone 工具，不提供诊断或治疗。',
    features: '读取用户授权的健康数据并展示趋势；展示授权拒绝状态，用户可以删除本地数据，不预测疾病。',
    platform: 'iPhone'
  });

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  const tasks = taskPlan.priorityTasks.map((item) => item.task).join('\n');
  assert.match(tasks, /HealthKit/);
  assert.match(tasks, /授权拒绝/);
  assert.match(tasks, /删除本地健康趋势数据/);
  assert.match(tasks, /非诊断/);
  assert.match(tasks, /本地模拟|模拟数据/);
  assert.ok(taskPlan.executionBoundaries.some((item) => item.phase === 'execute' && item.status === 'blocked'));
});

test('SaaS handoff covers every explicit membership goal', () => {
  const root = workspace();
  existingWebMembershipProject(root, '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；第一阶段仅使用本地假数据，不连接真实支付，也不要发布。');

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  const required = new Set(['goal:web-entry', 'goal:anonymous-browsing', 'goal:login-flow', 'goal:membership-state', 'goal:membership-entitlement']);
  const covered = new Set(taskPlan.goalCoverage.filter((item) => item.status === 'covered').map((item) => item.goalId));
  for (const goalId of required) assert.equal(covered.has(goalId), true, goalId);
  assert.ok(taskPlan.priorityTasks.some((item) => item.goalIds.includes('goal:web-entry')));
  assert.ok(taskPlan.priorityTasks.some((item) => item.goalIds.includes('goal:membership-entitlement')));
  assert.doesNotMatch(taskPlan.priorityTasks.map((item) => item.task).join('\n'), /(?:实现|接入|连接|启用).{0,8}真实支付/);
});

test('Node CLI handoff covers JSON and text compatibility without UI goals', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'report-cli', type: 'module', bin: { report: 'bin/report.js' } }));
  write(root, 'bin/report.js', '#!/usr/bin/env node\nconsole.log("items: 0");\n');
  write(root, 'test/report.test.js', 'import test from "node:test";\ntest("report", () => {});\n');
  existingIntake(root, '给现有 report 命令增加 --json 输出，并保留现有文本输出；不要改造成网页、云服务或账号系统。');

  planWorkspace(root);

  const taskPlan = readJSON(root, path.posix.join(latest(root).runPath, 'task-plan.json'));
  const covered = new Set(taskPlan.goalCoverage.filter((item) => item.status === 'covered').map((item) => item.goalId));
  assert.equal(covered.has('goal:cli-json'), true);
  assert.equal(covered.has('goal:cli-text-compatibility'), true);
  assert.doesNotMatch(taskPlan.priorityTasks.map((item) => item.task).join('\n'), /页面 UI|网页入口/);
});

test('goal coverage validator rejects a handoff with an uncovered required goal', () => {
  const result = validateGoalCoverage([
    { goalId: 'goal:web-entry', label: '网页登录入口' }
  ], [
    { taskId: 'task-login-data', goalIds: ['goal:login-flow'] }
  ], []);

  assert.equal(result.valid, false);
  assert.equal(result.goals[0].status, 'missing');
  assert.equal(result.goals[0].blockingReason, null);
});

test('sandbox execution context authorizes prepare and validate without durable production approval', () => {
  const context = sandboxExecutionContext(['current temporary worktree']);

  assert.deepEqual(context, {
    executionMode: 'sandbox_implementation',
    authorizedScope: ['current temporary worktree'],
    allowPrepare: true,
    allowValidate: true,
    allowProductionEffects: false
  });
  assert.equal(Object.hasOwn(context, 'ownerConfirmed'), false);
  assert.equal(Object.hasOwn(context, 'allowExecute'), false);
});

test('risk finding that raises task priority satisfies the decision impact contract', () => {
  const validation = validateAgentEvidence({
    roleId: 'security_privacy',
    triggerReason: 'signal:login',
    evidence: [{ source: 'derived:login', detail: '确定性规则识别出登录需求。' }],
    independentFinding: '登录流程涉及真实账号数据边界风险。',
    protectedConstraint: '不得把真实密码写入仓库。',
    generatedTask: '定义账号数据的最小保护边界。',
    decisionImpact: {
      changedPlanDecision: '将账号数据保护任务提升为 high 优先级。',
      affectedTaskIds: ['task-security'],
      impactType: 'changed_priority'
    },
    planContribution: { agentIds: ['security_privacy'] }
  });

  assert.equal(validation.valid, true);
  assert.equal(validation.unusedEvidence, false);
});

test('two roles contributing to one task retain both explainability sources', () => {
  const first = {
    agentIds: ['security_privacy'],
    sections: ['firstStage'],
    tasks: ['定义账号数据的最小保护边界。'],
    evidence: [{ source: 'derived:login', detail: '登录需求规则证据。' }],
    triggerReasons: ['signal:login'],
    triggerReason: 'signal:login',
    independentFinding: '登录流程涉及账号数据边界风险。',
    decisionImpact: {
      changedPlanDecision: '将账号保护任务提升为 high 优先级。',
      affectedTaskIds: ['task-security'],
      impactType: 'changed_priority'
    }
  };
  const second = {
    ...first,
    agentIds: ['privacy_request_ops'],
    evidence: [{ source: 'derived:login', detail: '账号删除规则证据。' }],
    independentFinding: '账号删除流程也影响同一保护边界。',
    decisionImpact: {
      changedPlanDecision: '将账号删除约束合并到同一保护任务。',
      affectedTaskIds: ['task-security'],
      impactType: 'created_task'
    }
  };

  const records = priorityTaskRecords([first, second], ['firstStage']);
  assert.equal(records.length, 1);
  assert.deepEqual(records[0].contributingRoles, ['security_privacy', 'privacy_request_ops']);
  assert.equal(records[0].evidence.length, 2);
  assert.equal(records[0].contributionImpacts.length, 2);
});

test('removing a low-contribution merged role leaves the task decision unchanged', () => {
  const primary = {
    agentIds: ['backend_engineer'],
    sections: ['firstStage'],
    tasks: ['定义匿名和已登录状态。'],
    evidence: [{ source: 'derived:login', detail: '登录需求规则证据。' }],
    triggerReasons: ['signal:login'],
    triggerReason: 'signal:login',
    independentFinding: '登录状态需要区分匿名和已登录。',
    decisionImpact: {
      changedPlanDecision: '将登录状态任务加入优先任务池。',
      affectedTaskIds: ['task-login'],
      impactType: 'created_task'
    }
  };
  const duplicate = {
    ...primary,
    agentIds: ['database_engineer'],
    evidence: [{ source: 'derived:login', detail: '账号字段规则证据。' }]
  };
  const withBoth = priorityTaskRecords([primary, duplicate], ['firstStage']);
  const withoutLow = priorityTaskRecords([primary], ['firstStage']);

  assert.deepEqual(
    withBoth.map(({ taskId, task, priority }) => ({ taskId, task, priority })),
    withoutLow.map(({ taskId, task, priority }) => ({ taskId, task, priority }))
  );
  assert.equal(withBoth[0].contributionImpacts[1].lowContribution, true);
});

test('plan creates a conservative first-stage plan for a new iPhone project', () => {
  const root = workspace();
  newIntake(root);

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.equal(result.state, 'ready');
  assert.match(taskPlan, /只面向 iPhone/);
  assert.doesNotMatch(taskPlan, /iPad|Android|Windows/);
  assert.equal(agentOutput(root, 'ios_engineer').status, 'completed');
  assert.equal(fs.existsSync(path.join(root, 'project.pbxproj')), false);
});

test('plan keeps a new Mac project specific to macOS', () => {
  const root = workspace();
  newIntake(root, { idea: '一个整理本地文件的工具', features: '选择文件并整理名称', platform: 'Mac' });

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /只面向 macOS/);
  assert.doesNotMatch(taskPlan, /iPhone|iPad|Android|Windows/);
  assert.doesNotMatch(taskPlan, /TestFlight|App Store/);
  assert.doesNotMatch(taskPlan, /源码已创建|工程已创建/);
});

test('plan does not choose a framework for a new web project', () => {
  const root = workspace();
  newIntake(root, { idea: '一个展示旅行清单的网页', features: '添加地点并查看清单', platform: '网页' });

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /不预先指定框架/);
  assert.doesNotMatch(taskPlan, /React|Vue|Next\.js|Svelte/);
  assert.doesNotMatch(taskPlan, /TestFlight|App Store/);
  assert.equal(agentOutput(root, 'website_frontend').status, 'completed');
});

test('plan keeps planning ready and records a pending decision when platform is undecided', () => {
  const root = workspace();
  newIntake(root, { platform: '还没想好' });

  const result = planWorkspace(root);
  const status = readJSON(root, '.jumao/status.json');
  const run = latest(root);
  const runManifest = manifest(root);
  const taskPlanJSON = readJSON(root, path.posix.join(run.runPath, 'task-plan.json'));
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');
  const expectedDecision = '动手之前先定一件事：第一版做 iPhone、Mac 电脑，还是网页？';

  assert.equal(result.ok, true, result.error);
  assert.equal(result.state, 'ready');
  assert.equal(result.platformPending, true);
  assert.equal(result.pendingDecision, expectedDecision);
  assert.deepEqual(result.blockingQuestions, []);
  assert.equal(status.cat.state, 'ready');
  assert.equal(status.platformPending, true);
  assert.equal(status.pendingDecision, expectedDecision);
  assert.equal(run.platformPending, true);
  assert.equal(runManifest.platformPending, true);
  assert.equal(taskPlanJSON.platformPending, true);
  assert.equal(taskPlanJSON.pendingDecision, expectedDecision);
  assert.match(taskPlan, /与使用方式无关/);
  assert.match(taskPlan, /暂不创建任何特定平台的源码工程/);
  assert.match(taskPlan, /真正阻止开发的问题\n\n- 没有/);
  assert.doesNotMatch(taskPlan, /Swift|SwiftUI|React|Vue|Next\.js|Svelte/);
  assert.equal(agentOutput(root, 'ios_engineer').status, 'skipped');
  assert.equal(agentOutput(root, 'website_frontend').status, 'skipped');
  assert.equal(agentOutput(root, 'project_tech_lead').status, 'completed');
  assert.ok(agentOutput(root, 'project_tech_lead').decisions.includes(expectedDecision));
  assert.equal(fs.existsSync(path.join(root, 'package.json')), false);
});

test('plan analyzes an existing Swift project from real files and tests', () => {
  const root = workspace();
  mkdir(root, 'Mood.xcodeproj');
  write(root, 'Sources/LoginView.swift', 'import SwiftUI\nstruct LoginView: View { var body: some View { Text("登录") } }\n');
  write(root, 'Tests/LoginViewTests.swift', 'import XCTest\nfinal class LoginViewTests: XCTestCase {}\n');
  write(root, 'product/scope-gate.md', '# Scope\n\n- 必须保留现有离线记录。\n');
  existingIntake(root, '修复 LoginView 登录按钮点击后没有反馈');

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /Sources\/LoginView\.swift/);
  assert.match(taskPlan, /Tests\/LoginViewTests\.swift/);
  assert.match(taskPlan, /product\/scope-gate\.md:3/);
  assert.equal(agentOutput(root, 'ios_engineer').status, 'completed');
});

test('plan analyzes an existing Python project without inventing a different stack', () => {
  const root = workspace();
  write(root, 'pyproject.toml', '[project]\nname = "reports"\n');
  write(root, 'src/report_export.py', 'def export_report():\n    return "report"\n');
  write(root, 'tests/test_report_export.py', 'def test_export_report():\n    assert True\n');
  existingIntake(root, '修复 report export 导出报表为空的问题');

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /src\/report_export\.py/);
  assert.match(taskPlan, /tests\/test_report_export\.py/);
  assert.doesNotMatch(taskPlan, /Xcode 工程/);
  assert.doesNotMatch(taskPlan, /TestFlight|App Store/);
  assert.ok(agentOutput(root, 'project_tech_lead').evidence.some((item) => /Python/.test(item.detail)));
});

test('semantic-equivalent web membership requests activate the same platform-compatible Agents', () => {
  const englishRoot = workspace();
  const chineseRoot = workspace();
  existingWebMembershipProject(
    englishRoot,
    'Add email login and subscription membership to the existing web catalog. Keep anonymous browsing. Do not connect real payment and do not release.'
  );
  existingWebMembershipProject(
    chineseRoot,
    '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；不要连接真实支付，也不要发布。'
  );

  planWorkspace(englishRoot);
  planWorkspace(chineseRoot);

  const comparedAgents = [
    'website_frontend', 'backend_engineer', 'database_engineer', 'security_privacy',
    'finance_tax', 'support_operations', 'iap_revenue_ops', 'app_store_submission',
    'sre_stability', 'remote_config_gray_release', 'device_lab_test_data'
  ];
  const englishStatuses = Object.fromEntries(comparedAgents.map((id) => [id, agentOutput(englishRoot, id).status]));
  const chineseStatuses = Object.fromEntries(comparedAgents.map((id) => [id, agentOutput(chineseRoot, id).status]));

  assert.deepEqual(englishStatuses, chineseStatuses);
  for (const id of ['website_frontend', 'backend_engineer', 'database_engineer', 'security_privacy', 'finance_tax', 'support_operations']) {
    assert.equal(englishStatuses[id], 'completed', id);
  }
  for (const id of ['iap_revenue_ops', 'app_store_submission', 'sre_stability', 'remote_config_gray_release', 'device_lab_test_data']) {
    assert.equal(englishStatuses[id], 'skipped', id);
  }
});

test('negation scope stops at Chinese and English contrast clauses', () => {
  const chineseRoot = workspace();
  const englishRoot = workspace();
  existingWebMembershipProject(
    chineseRoot,
    '现阶段不要发布但保留登录，并增加订阅会员；不要连接真实支付。'
  );
  existingWebMembershipProject(
    englishRoot,
    'Do not release but keep login and add subscription membership to the web catalog. Do not connect real payment.'
  );

  planWorkspace(chineseRoot);
  planWorkspace(englishRoot);

  for (const root of [chineseRoot, englishRoot]) {
    assert.equal(agentOutput(root, 'backend_engineer').status, 'completed');
    assert.equal(agentOutput(root, 'app_store_submission').status, 'skipped');
    assert.equal(agentOutput(root, 'sre_stability').status, 'skipped');
    assert.ok(agentOutput(root, 'backend_engineer').negativeSignals.includes('release'));
  }
});

test('completed Agents separate intent project and role evidence without generic file evidence inflation', () => {
  const root = workspace();
  existingWebMembershipProject(
    root,
    '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；不要连接真实支付，也不要发布。'
  );

  planWorkspace(root);

  const backend = agentOutput(root, 'backend_engineer');
  assert.equal(backend.status, 'completed');
  assert.ok(backend.triggerReasons.includes('signal:login'));
  assert.ok(backend.negativeSignals.includes('release'));
  assert.ok(backend.negativeSignals.includes('payment'));
  assert.ok(backend.intentEvidence.some((item) => item.source === 'intake.answers.requestedChange'));
  assert.ok(backend.projectEvidence.some((item) => /Web/.test(item.detail)));
  assert.ok(backend.roleEvidence.some((item) => /src\/access\.js/.test(item.source)));
  assert.equal(backend.roleEvidence.some((item) => item.source === 'file:package.json'), false);
  assert.ok(backend.planContribution.tasks.length > 0);

  const iap = agentOutput(root, 'iap_revenue_ops');
  assert.equal(iap.status, 'skipped');
  assert.match(iap.skippedReason, /Apple 平台/);
});

test('manifest records normalized platforms and negative signals as stable machine-readable input', () => {
  const root = workspace();
  existingWebMembershipProject(
    root,
    '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；不要连接真实支付，也不要发布。'
  );

  planWorkspace(root);
  const runManifest = manifest(root);

  assert.deepEqual(runManifest.input.platforms, ['Web']);
  assert.deepEqual(runManifest.input.negativeSignals, ['payment', 'release']);
});

test('web login membership plan includes Agent-derived implementation tasks without Apple release work', () => {
  const root = workspace();
  existingWebMembershipProject(
    root,
    '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；第一阶段仅使用本地假数据，不连接真实支付，也不要发布。'
  );

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');
  const run = latest(root);
  const taskPlanJSON = readJSON(root, path.posix.join(run.runPath, 'task-plan.json'));

  assert.equal(result.state, 'ready');
  assert.match(taskPlan, /定义匿名、已登录和会员状态/);
  assert.match(taskPlan, /本地假账号和假会员状态/);
  assert.match(taskPlan, /不保存真实密码或支付信息/);
  assert.match(taskPlan, /保留匿名浏览/);
  assert.doesNotMatch(taskPlan, /StoreKit|App Store|TestFlight/);
  assert.ok(taskPlanJSON.contributions.some((item) => item.agentIds.includes('backend_engineer')));
  assert.ok(taskPlanJSON.priorityTasks.length > 0);
  for (const priorityTask of taskPlanJSON.priorityTasks) {
    assert.ok(priorityTask.taskId);
    assert.ok(['high', 'normal'].includes(priorityTask.priority));
    assert.ok(priorityTask.task);
    assert.ok(priorityTask.contributingRoles.length > 0);
    assert.ok(priorityTask.evidence.length > 0);
    assert.ok(priorityTask.triggerReason);
    assert.ok(priorityTask.findings.length > 0);
    assert.ok(priorityTask.contributionImpacts.length > 0);
    assert.deepEqual(priorityTask.decisionImpact, priorityTask.contributionImpacts);
    for (const impact of priorityTask.contributionImpacts) {
      assert.ok(impact.changedPlanDecision);
      assert.ok(impact.affectedTaskIds.includes(priorityTask.taskId));
      assert.ok([
        'created_task', 'removed_risk', 'protected_constraint', 'changed_priority', 'merged_task'
      ].includes(impact.impactType));
    }
  }
  assert.ok(taskPlanJSON.priorityTasks.some((priorityTask) => priorityTask.priority === 'high'));
  assert.equal(taskPlanJSON.firstStage.filter((item) => item.includes('后端工程师 Agent')).length, 1);
  assert.equal(taskPlan.split('must keep anonymous catalog browsing available.').length - 1, 1);
});

test('golden local macOS file tool does not invent cloud or database work', () => {
  const root = workspace();
  newIntake(root, {
    idea: '一个整理本地文件的 Mac 工具',
    features: '选择本地文件并整理名称，不上传任何内容',
    platform: 'Mac'
  });

  planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(agentOutput(root, 'backend_engineer').status, 'skipped');
  assert.equal(agentOutput(root, 'database_engineer').status, 'skipped');
  assert.equal(agentOutput(root, 'devops_cloud').status, 'skipped');
  assert.match(taskPlan, /只面向 macOS/);
  assert.doesNotMatch(taskPlan, /生产数据库|部署生产环境|云同步/);
});

test('golden iPhone health trend project keeps claims evidence-bound', () => {
  const root = workspace();
  newIntake(root, {
    idea: '一个查看健康趋势的 iPhone 工具，不提供诊断或治疗',
    features: '读取用户授权的健康数据并展示趋势，不预测疾病',
    platform: 'iPhone'
  });

  planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  for (const id of ['health_content', 'medical_claims_review', 'algorithm_validation_evidence', 'security_privacy', 'device_lab_test_data']) {
    assert.equal(agentOutput(root, id).status, 'completed', id);
  }
  assert.match(taskPlan, /不得|不提供诊断|不能视为/);
  assert.doesNotMatch(taskPlan, /实现诊断|实现治疗|预测疾病结果/);
});

test('golden Node CLI change stays CLI-focused and skips UI and store roles', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({
    name: 'sample-cli',
    type: 'module',
    bin: { sample: 'bin/sample.js' },
    scripts: { test: 'node --test' }
  }));
  write(root, 'bin/sample.js', '#!/usr/bin/env node\nconsole.log("sample");\n');
  write(root, 'test/cli.test.js', 'import test from "node:test";\ntest("runs", () => {});\n');
  existingIntake(root, '给 sample 命令增加 --json 输出，并保留现有文本输出');

  planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  for (const id of ['ui_ux', 'website_frontend', 'ios_engineer', 'app_store_submission', 'iap_revenue_ops']) {
    if (id === 'ui_ux') continue;
    assert.equal(agentOutput(root, id).status, 'skipped', id);
  }
  assert.match(agentOutput(root, 'project_tech_lead').findings.join('\n'), /Node CLI|JavaScript|npm/);
  assert.doesNotMatch(taskPlan, /页面骨架|App Store|StoreKit|TestFlight/);
});

test('plan handles a fuzzy existing folder without fabricating affected modules', () => {
  const root = workspace();
  write(root, 'notes.txt', '只有几条项目想法。\n');
  existingIntake(root, '整理当前说明，让内容更清楚');

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /没有足够源码或配置证据/);
  assert.equal(manifest(root).agents.length, 44);
});

test('plan records a missing intake as blocked instead of creating a questionnaire', () => {
  const root = workspace();

  const result = planWorkspace(root);
  const runManifest = manifest(root);

  assert.equal(result.ok, true, result.error);
  assert.equal(result.state, 'blocked');
  assert.equal(runManifest.agents.length, 44);
  assert.ok(runManifest.counts.blocked > 0);
  assert.match(readText(root, 'tasks/jumao-agent-plan.md'), /还没回答开头的几个问题。先在橘猫里把它们答完，就能开始规划。/);
});

test('plan safely records corrupt intake and exits non-zero through the CLI', () => {
  const root = workspace();
  write(root, '.jumao/intake-answers.json', '{not-json');

  const command = runCLI(root, '--json');
  const output = JSON.parse(command.stdout);
  const runManifest = manifest(root);
  const status = readJSON(root, '.jumao/status.json');

  assert.equal(command.status, 1);
  assert.equal(output.ok, false);
  assert.equal(output.state, 'blocked');
  assert.equal(runManifest.agents.length, 44);
  assert.equal(agentOutput(root, 'founder_decision').status, 'failed');
  assert.equal(status.cat.state, 'blocked');
});

test('manifest contains all 44 registered Agents with the exact auditable output schema', () => {
  const root = workspace();
  newIntake(root);
  planWorkspace(root);

  const run = latest(root);
  const runManifest = manifest(root);
  const manifestIds = runManifest.agents.map((agent) => agent.agentId).sort();
  const registryIds = responsibilityAgents.map((agent) => agent.id).sort();

  assert.equal(runManifest.agents.length, 44);
  assert.equal(Object.values(runManifest.counts).reduce((sum, count) => sum + count, 0), 44);
  assert.deepEqual(manifestIds, registryIds);
  assert.equal(runManifest.groups.length, 8);
  assert.deepEqual(runManifest.groups.map((group) => group.groupId), agentGroups.map((group) => group.id));
  for (const file of ['manifest.json', 'planning-summary.md', 'task-plan.json']) {
    assert.equal(fs.existsSync(path.join(root, run.runPath, file)), true, file);
  }
  for (const item of runManifest.agents) {
    const output = readJSON(root, path.posix.join(run.runPath, item.output));
    assert.deepEqual(Object.keys(output), agentOutputKeys);
    assert.ok(['completed', 'skipped', 'blocked', 'failed'].includes(output.status));
    if (output.status === 'completed') {
      assert.equal(output.roleId, item.agentId);
      assert.ok(output.triggerReasons.length > 0, item.agentId);
      assert.ok(output.triggerReason, item.agentId);
      assert.ok(output.intentEvidence.length > 0 || output.projectEvidence.length > 0 || output.roleEvidence.length > 0, item.agentId);
      assert.equal(output.evidenceQuality.valid, true, item.agentId);
      assert.ok(output.independentFinding, item.agentId);
      assert.ok(['changed_plan', 'no_change'].includes(output.assessmentOutcome), item.agentId);
      if (output.assessmentOutcome === 'changed_plan') {
        assert.ok(output.protectedConstraint || output.generatedTask, item.agentId);
        assert.ok(output.decisionImpact, item.agentId);
        assert.ok(output.changedPlanDecision, item.agentId);
        assert.ok(Array.isArray(output.affectedTaskIds), item.agentId);
        assert.ok([
          'created_task', 'removed_risk', 'protected_constraint', 'changed_priority', 'merged_task'
        ].includes(output.impactType), item.agentId);
        assert.ok(output.planContribution, item.agentId);
      } else {
        assert.equal(output.generatedTask, null, item.agentId);
        assert.equal(output.protectedConstraint, null, item.agentId);
        assert.equal(output.decisionImpact, null, item.agentId);
        assert.equal(output.planContribution, null, item.agentId);
      }
      assert.equal(output.unusedEvidence, false, item.agentId);
      assert.equal(output.incompleteEvidence, false, item.agentId);
      if (!output.triggerReasons.includes('runtime-baseline')) {
        assert.ok(
          output.roleEvidence.length > 0 || output.intentEvidence.some((evidence) => evidence.source.startsWith('derived:')),
          `${item.agentId} needs role or explicit intent evidence`
        );
      }
    }
    if (output.status === 'skipped') {
      assert.equal(output.planContribution, null, item.agentId);
      if (output.incompleteEvidence) assert.match(output.skippedReason, /证据契约不完整/);
    }
  }
});

test('four representative plans produce complete, evidence-backed, non-repetitive artifacts', () => {
  const cases = [
    {
      name: 'new iPhone',
      setup(root) { newIntake(root); },
      exactRequest: '一个记录心情的小工具'
    },
    {
      name: 'new undecided',
      setup(root) { newIntake(root, { platform: '还没想好' }); },
      exactRequest: '一个记录心情的小工具',
      undecided: true
    },
    {
      name: 'existing Swift',
      setup(root) {
        mkdir(root, 'Focus.xcodeproj');
        write(root, 'Sources/FocusView.swift', 'import SwiftUI\nstruct FocusView {}\n');
        write(root, 'Tests/FocusTests.swift', 'import XCTest\n');
        existingIntake(root, '修复 FocusView 保存后界面不更新');
      },
      exactRequest: '修复 FocusView 保存后界面不更新'
    },
    {
      name: 'existing Python',
      setup(root) {
        write(root, 'pyproject.toml', '[project]\nname = "reports"\n');
        write(root, 'src/report.py', 'def render():\n    return "report"\n');
        write(root, 'tests/test_report.py', 'def test_render():\n    assert True\n');
        existingIntake(root, '修复 report 生成空内容');
      },
      exactRequest: '修复 report 生成空内容'
    }
  ];

  for (const item of cases) {
    const root = workspace();
    item.setup(root);
    const result = planWorkspace(root);
    const run = latest(root);
    const runManifest = manifest(root);
    const taskPlanJSON = readJSON(root, path.posix.join(run.runPath, 'task-plan.json'));
    const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

    assert.equal(result.state, 'ready', item.name);
    assert.equal(runManifest.agents.length, 44, item.name);
    assert.equal(runManifest.groups.length, 8, item.name);
    assert.equal(runManifest.counts.failed, 0, item.name);
    assert.equal(runManifest.counts.blocked, 0, item.name);
    assert.ok(taskPlanJSON.firstStage.length >= 3, item.name);
    assert.equal(taskPlan.split(item.exactRequest).length - 1, 1, item.name);
    assert.doesNotMatch(taskPlan, /赋能|抓手|协同矩阵|优先级矩阵/, item.name);

    for (const entry of runManifest.groups) {
      assert.equal(fs.existsSync(path.join(root, run.runPath, entry.output)), true, `${item.name}:${entry.groupId}`);
    }
    for (const entry of runManifest.agents) {
      const output = readJSON(root, path.posix.join(run.runPath, entry.output));
      if (output.status === 'completed') assert.ok(output.evidence.length > 0, `${item.name}:${entry.agentId}`);
      if (output.status === 'skipped') assert.ok(output.skippedReason, `${item.name}:${entry.agentId}`);
    }

    if (item.undecided) {
      assert.equal(taskPlanJSON.platformPending, true, item.name);
      assert.doesNotMatch(taskPlan, /Swift|SwiftUI|React|Vue|Next\.js|Svelte/, item.name);
    }
  }
});

test('irrelevant Agents are skipped and all-skipped groups remain idle', () => {
  const root = workspace();
  newIntake(root);
  planWorkspace(root);

  for (const id of ['backend_engineer', 'database_engineer', 'finance_tax', 'iap_revenue_ops', 'health_content']) {
    const output = agentOutput(root, id);
    assert.equal(output.status, 'skipped', id);
    assert.ok(output.skippedReason, id);
    assert.equal(output.evidence.length, 0, id);
  }
  const revenueGroup = readJSON(root, '.jumao/status.json').agentBoard.groups
    .find((group) => group.id === 'revenue_operations');
  assert.equal(revenueGroup.state, 'idle');
});

test('relevant Agents complete real analysis and cite trigger evidence', () => {
  const root = workspace();
  newIntake(root, {
    idea: '一个让用户购买会员的 iPhone 工具',
    features: '用户可以订阅会员并恢复购买'
  });
  planWorkspace(root);

  for (const id of ['finance_tax', 'iap_revenue_ops', 'support_operations']) {
    const output = agentOutput(root, id);
    assert.equal(output.status, 'completed', id);
    assert.ok(output.evidence.some((item) => item.source === 'derived:payment'), id);
    assert.ok(output.findings.length > 0, id);
    assert.ok(output.tasks.length > 0, id);
  }
});

test('generic intake does not fabricate login payment subscription cloud or health capabilities', () => {
  const root = workspace();
  newIntake(root);
  write(root, 'api-secret.txt', 'PRIVATE_VALUE_MUST_NOT_LEAK');
  planWorkspace(root);

  const run = latest(root);
  const allOutputs = fs.readdirSync(path.join(root, run.runPath, 'agents'))
    .map((file) => readText(root, path.posix.join(run.runPath, 'agents', file)))
    .join('\n');

  for (const id of ['backend_engineer', 'finance_tax', 'iap_revenue_ops', 'devops_cloud', 'health_content']) {
    assert.equal(agentOutput(root, id).status, 'skipped', id);
  }
  assert.equal(allOutputs.includes('PRIVATE_VALUE_MUST_NOT_LEAK'), false);
  assert.equal(readText(root, 'tasks/jumao-agent-plan.md').includes('ai-note-helper'), false);
});

test('existing project protections come from real tests build files and product documents', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'existing-web', scripts: { test: 'node --test' } }));
  write(root, 'src/editor.js', 'export function saveDraft() {}\n');
  write(root, 'test/editor.test.js', 'import test from "node:test";\n');
  write(root, 'product/scope-gate.md', '# Scope\n\n- 不得删除现有草稿恢复能力。\n');
  existingIntake(root, '修复 editor 保存草稿后内容消失');

  const result = planWorkspace(root);
  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');

  assert.equal(result.ok, true, result.error);
  assert.match(taskPlan, /保留并运行现有测试/);
  assert.match(taskPlan, /保持现有构建方式可用：npm/);
  assert.match(taskPlan, /product\/scope-gate\.md:3/);
  assert.match(taskPlan, /不得删除现有草稿恢复能力/);
  assert.equal(readText(root, 'product/scope-gate.md'), '# Scope\n\n- 不得删除现有草稿恢复能力。\n');
});

test('repeated runs preserve history, reuse unchanged input, and force creates a new run', () => {
  const root = workspace();
  newIntake(root);

  const first = planWorkspace(root);
  const reused = planWorkspace(root);
  assert.equal(reused.reused, true);
  assert.equal(reused.runId, first.runId);

  newIntake(root, { features: '记录一次心情并按日期查看记录' });
  const changed = planWorkspace(root);
  assert.notEqual(changed.runId, first.runId);
  assert.equal(fs.existsSync(path.join(root, changed.runPath, 'previous-task-plan.md')), true);

  const forced = planWorkspace(root, { force: true });
  assert.notEqual(forced.runId, changed.runId);
  assert.equal(fs.readdirSync(path.join(root, '.jumao/runs')).length, 3);
});

test('write failure records a failed run and never leaves status checking', () => {
  const root = workspace();
  newIntake(root);
  write(root, 'tasks', 'this path intentionally blocks the tasks directory');

  const result = planWorkspace(root);
  const status = readJSON(root, '.jumao/status.json');
  const runManifest = manifest(root);

  assert.equal(result.ok, false);
  assert.notEqual(status.cat.state, 'checking');
  assert.equal(status.cat.state, 'blocked');
  assert.ok(status.failedAgents > 0);
  assert.equal(fs.readdirSync(path.join(root, '.jumao')).some((name) => name.includes('.tmp-')), false);
  assert.equal(runManifest.agents.length, 44);
  assert.equal(agentOutput(root, 'documentation_delivery').status, 'failed');
  assert.deepEqual(Object.keys(agentOutput(root, 'documentation_delivery')), agentOutputKeys);
});

test('task plan has all ten Codex-ready sections without professional questionnaires', () => {
  const root = workspace();
  newIntake(root);
  planWorkspace(root);

  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');
  for (let index = 1; index <= 10; index += 1) assert.match(taskPlan, new RegExp(`## ${index}\\.`));
  assert.match(taskPlan, /先总结项目目标/);
  assert.match(taskPlan, /prepare 和 validate/);
  assert.match(taskPlan, /execute.*blocked/);
  assert.doesNotMatch(taskPlan, /在项目主人确认前，不要修改代码/);
  assert.doesNotMatch(taskPlan, /风险矩阵|优先级矩阵|架构方案问卷|专业验收标准问卷/);
});

test('plan --json emits stable machine-readable output with required status fields', () => {
  const root = workspace();
  newIntake(root);

  const firstCommand = runCLI(root, '--json');
  const secondCommand = runCLI(root, '--json');
  const first = JSON.parse(firstCommand.stdout);
  const second = JSON.parse(secondCommand.stdout);
  const status = readJSON(root, '.jumao/status.json');

  assert.equal(firstCommand.status, 0, firstCommand.stderr);
  assert.equal(firstCommand.stderr, '');
  assert.equal(secondCommand.status, 0, secondCommand.stderr);
  assert.equal(second.reused, true);
  assert.equal(second.runId, first.runId);
  assert.deepEqual(second.counts, first.counts);
  for (const key of [
    'runId', 'startedAt', 'completedAt', 'totalAgents', 'completedAgents',
    'skippedAgents', 'blockedAgents', 'failedAgents'
  ]) assert.ok(Object.hasOwn(status, key), key);
  assert.equal(status.totalAgents, 44);
  assert.equal(status.completedAgents, first.counts.completed);
  assert.equal(status.skippedAgents, first.counts.skipped);
  assert.equal(status.blockedAgents, first.counts.blocked);
  assert.equal(status.failedAgents, first.counts.failed);
});

test('plan --events-jsonl emits strict JSONL in real execution order', () => {
  const root = workspace();
  newIntake(root);

  const command = runCLI(root, '--events-jsonl');
  assert.equal(command.status, 0, command.stderr);
  assert.equal(command.stderr, '');
  const events = command.stdout.trim().split('\n').map((line) => JSON.parse(line));

  assert.equal(events.length, 1 + agentGroups.length * 2 + responsibilityAgents.length + 1);
  assert.equal(events[0].event, 'run.started');
  assert.equal(events.at(-1).event, 'run.completed');
  assert.equal(events[0].groups.length, 8);
  assert.equal(events[0].totalAgents, 44);
  for (const event of events) {
    for (const key of [
      'runId', 'timestamp', 'event', 'groupId', 'agentId', 'agentStatus',
      'completedAgents', 'skippedAgents', 'blockedAgents', 'failedAgents', 'totalAgents'
    ]) assert.ok(Object.hasOwn(event, key), `${event.event}.${key}`);
  }

  let cursor = 1;
  for (const group of agentGroups) {
    assert.equal(events[cursor].event, 'group.started');
    assert.equal(events[cursor].groupId, group.id);
    cursor += 1;
    const expectedAgents = responsibilityAgents.filter((agent) => agent.groupId === group.id);
    for (const agent of expectedAgents) {
      assert.match(events[cursor].event, /^agent\.(completed|skipped|blocked|failed)$/);
      assert.equal(events[cursor].agentId, agent.id);
      cursor += 1;
    }
    assert.equal(events[cursor].event, 'group.completed');
    assert.equal(events[cursor].groupId, group.id);
    cursor += 1;
  }
});

test('events final Agent and group states match written manifest artifacts', () => {
  const root = workspace();
  newIntake(root);

  const command = runCLI(root, '--events-jsonl');
  const events = command.stdout.trim().split('\n').map((line) => JSON.parse(line));
  const runManifest = manifest(root);
  const agentEvents = new Map(
    events.filter((event) => event.agentId).map((event) => [event.agentId, event.agentStatus])
  );
  const groupEvents = events.filter((event) => event.event === 'group.completed');

  assert.equal(agentEvents.size, 44);
  assert.equal(groupEvents.length, 8);
  for (const agent of runManifest.agents) assert.equal(agentEvents.get(agent.agentId), agent.status);
  assert.deepEqual(events.at(-1).completedAgents, runManifest.counts.completed);
  assert.deepEqual(events.at(-1).skippedAgents, runManifest.counts.skipped);
  assert.deepEqual(events.at(-1).blockedAgents, runManifest.counts.blocked);
  assert.deepEqual(events.at(-1).failedAgents, runManifest.counts.failed);
});

test('events report failed runs and status never remains checking', () => {
  const root = workspace();
  newIntake(root);
  write(root, 'tasks', 'block task plan directory');

  const command = runCLI(root, '--events-jsonl');
  const events = command.stdout.trim().split('\n').map((line) => JSON.parse(line));
  const status = readJSON(root, '.jumao/status.json');

  assert.equal(command.status, 1);
  assert.equal(events.at(-1).event, 'run.failed');
  assert.notEqual(status.cat.state, 'checking');
  assert.equal(events.at(-1).failedAgents, manifest(root).counts.failed);
  const failedAgentEvent = events.find((event) => event.event === 'agent.failed');
  const failedGroup = manifest(root).groups.find((group) => group.groupId === failedAgentEvent.groupId);
  assert.equal(failedAgentEvent.groupName, '产品与设计 Agent 组');
  assert.deepEqual(failedAgentEvent.groupCounts, failedGroup.counts);
});

test('events support workspaces with Chinese characters and spaces', () => {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-plan-path-'));
  const root = path.join(parent, '喝水 App 项目');
  fs.mkdirSync(root);
  newIntake(root);

  const command = runCLI(root, '--events-jsonl');
  const finalEvent = JSON.parse(command.stdout.trim().split('\n').at(-1));
  assert.equal(command.status, 0, command.stderr);
  assert.equal(finalEvent.event, 'run.completed');
  assert.equal(finalEvent.state, 'ready');
});

test('events distinguish reused results from forced executions', () => {
  const root = workspace();
  newIntake(root);
  const first = runCLI(root, '--events-jsonl');
  const firstEvents = first.stdout.trim().split('\n').map((line) => JSON.parse(line));
  const reused = runCLI(root, '--events-jsonl');
  const reusedEvents = reused.stdout.trim().split('\n').map((line) => JSON.parse(line));
  const forced = runCLI(root, '--events-jsonl', '--force');
  const forcedEvents = forced.stdout.trim().split('\n').map((line) => JSON.parse(line));

  assert.equal(reusedEvents.length, 2);
  assert.deepEqual(reusedEvents.map((event) => event.event), ['run.started', 'run.completed']);
  assert.ok(reusedEvents.every((event) => event.reused));
  assert.equal(reusedEvents[0].runId, firstEvents[0].runId);
  assert.equal(forcedEvents[0].reused, false);
  assert.notEqual(forcedEvents[0].runId, firstEvents[0].runId);
  assert.equal(forcedEvents.filter((event) => event.agentId).length, 44);
});

test('all eight groups execute sequentially and hand off structured context', () => {
  const root = workspace();
  newIntake(root);
  planWorkspace(root);

  const run = latest(root);
  const groups = manifest(root).groups.map((entry) => readJSON(root, path.posix.join(run.runPath, entry.output)));

  assert.deepEqual(groups.map((group) => group.sequence), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(groups[0].dependsOnGroupId, null);
  for (let index = 1; index < groups.length; index += 1) {
    assert.equal(groups[index].executionMode, 'sequential');
    assert.equal(groups[index].dependsOnGroupId, groups[index - 1].groupId);
    assert.equal(groups[index].receivedContext.fromGroupId, groups[index - 1].groupId);
  }
});
