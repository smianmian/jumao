import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { responsibilityAgents, agentGroups } from '../src/core/agent-registry.js';
import { planWorkspace } from '../src/core/planning-runtime.js';

const repoRoot = path.resolve(new URL('..', import.meta.url).pathname);
const cli = path.join(repoRoot, 'bin', 'jumao.js');
const agentOutputKeys = [
  'agentId', 'groupId', 'status', 'summary', 'evidence', 'findings', 'decisions',
  'protections', 'tasks', 'blockingQuestions', 'skippedReason', 'error'
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

function agentOutput(root, agentId) {
  const run = latest(root);
  return readJSON(root, path.posix.join(run.runPath, 'agents', `${agentId}.json`));
}

function runCLI(root, ...args) {
  return spawnSync(process.execPath, [cli, 'plan', root, ...args], { encoding: 'utf8' });
}

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

test('plan marks an undecided platform as the one true source-project blocker', () => {
  const root = workspace();
  newIntake(root, { platform: '还没想好' });

  const result = planWorkspace(root);
  const status = readJSON(root, '.jumao/status.json');

  assert.equal(result.ok, true, result.error);
  assert.equal(result.state, 'blocked');
  assert.deepEqual(result.blockingQuestions, ['你想先在哪儿用它？']);
  assert.equal(status.cat.state, 'blocked');
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
  assert.match(readText(root, 'tasks/jumao-agent-plan.md'), /请先在 Jumao Cat 或 jumao interview 中完成首轮问答/);
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
});

test('task plan has all ten Codex-ready sections without professional questionnaires', () => {
  const root = workspace();
  newIntake(root);
  planWorkspace(root);

  const taskPlan = readText(root, 'tasks/jumao-agent-plan.md');
  for (let index = 1; index <= 10; index += 1) assert.match(taskPlan, new RegExp(`## ${index}\\.`));
  assert.match(taskPlan, /先总结项目目标/);
  assert.match(taskPlan, /在项目主人确认前，不要修改代码/);
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
