import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  buildExecutionHandoff,
  validationBootstrapFor
} from '../src/core/execution-handoff.js';
import { planWorkspace } from '../src/core/planning-runtime.js';

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-executable-goal-'));
}

function write(root, relativePath, content) {
  const output = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content, 'utf8');
}

function existingIntake(root, requestedChange) {
  write(root, '.jumao/intake-answers.json', `${JSON.stringify({
    schemaVersion: 1,
    mode: 'existing_project',
    answers: { requestedChange }
  }, null, 2)}\n`);
}

function taskPlan(root) {
  const latest = JSON.parse(fs.readFileSync(path.join(root, '.jumao/latest-run.json'), 'utf8'));
  return JSON.parse(fs.readFileSync(path.join(root, latest.runPath, 'task-plan.json'), 'utf8'));
}

const sandbox = { allowPrepare: true, allowValidate: true, allowProductionEffects: false };
const webGoal = { goalId: 'goal:web-entry', label: '网页登录入口' };

test('goalId without an action cannot cover a handoff goal', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'web', goalIds: ['goal:web-entry'], target: 'index.html', doneWhen: 'page is reachable' }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, false);
  assert.equal(handoff.goalCoverage[0].reason, 'missing_action');
});

test('an action without a target cannot cover a handoff goal', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'web', goalIds: ['goal:web-entry'], action: 'create a page', doneWhen: 'page is reachable' }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, false);
  assert.equal(handoff.goalCoverage[0].reason, 'missing_target');
});

test('a task without doneWhen cannot enter a ready handoff', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'web', goalIds: ['goal:web-entry'], action: 'create a page', target: 'index.html' }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, false);
  assert.equal(handoff.goalCoverage[0].reason, 'missing_acceptance_check');
});

test('a blocked task cannot cover a handoff goal', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'web', goalIds: ['goal:web-entry'], action: 'create a page', target: 'index.html', doneWhen: 'page is reachable', blocked: true }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, false);
  assert.equal(handoff.goalCoverage[0].reason, 'blocked_goal');
});

test('a complete prepare task covers a handoff goal', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'web', goalIds: ['goal:web-entry'], action: 'create a page', target: 'index.html', doneWhen: 'page is reachable', phase: 'prepare' }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, true);
  assert.equal(handoff.goalCoverage[0].status, 'covered');
});

test('a Web membership request without an entry generates a minimal local entry task', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'catalog', type: 'module', scripts: { test: 'node --test' } }));
  write(root, 'src/access.js', 'export const canBrowseCatalog = () => true;\n');
  existingIntake(root, '为现有网页目录增加登录和会员，保留匿名浏览；仅使用本地假数据，不连接真实支付。');

  planWorkspace(root);

  const task = taskPlan(root).priorityTasks.find((item) => item.goalIds.includes('goal:web-entry'));
  assert.match(task.task, /创建.*本地.*入口|index\.html/);
  assert.match(task.task, /匿名.*登录.*会员|登录.*会员/);
});

test('an existing Web route is reused instead of creating a second entry', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'catalog', type: 'module' }));
  write(root, 'src/routes/catalog.js', 'export const CatalogRoute = () => null;\n');
  existingIntake(root, '在网页目录增加登录和会员，保留匿名浏览。');

  planWorkspace(root);

  const task = taskPlan(root).priorityTasks.find((item) => item.goalIds.includes('goal:web-entry'));
  assert.match(task.task, /src\/routes\/catalog\.js/);
  assert.doesNotMatch(task.task, /创建.*index\.html/);
});

test('a data-only task cannot substitute for a Web entry goal', () => {
  const handoff = buildExecutionHandoff({
    goals: [webGoal],
    tasks: [{ taskId: 'data', goalIds: ['goal:web-entry'], action: 'define membership fields', target: 'src/access.js', doneWhen: 'fields exist', surface: 'data' }],
    executionContext: sandbox
  });
  assert.equal(handoff.ready, false);
  assert.equal(handoff.goalCoverage[0].reason, 'missing_task');
});

test('membership handoff exposes an observable entitlement behavior', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'catalog', type: 'module' }));
  existingIntake(root, '为网页目录增加登录和会员，保留匿名浏览。');
  planWorkspace(root);
  const task = taskPlan(root).priorityTasks.find((item) => item.goalIds.includes('goal:membership-entitlement') && /完成条件/.test(item.task));
  assert.match(task.task, /权益/);
  assert.match(task.task, /完成条件|doneWhen/);
});

test('Web membership planning does not create a real payment task', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'catalog', type: 'module' }));
  existingIntake(root, '为网页目录增加登录和会员，保留匿名浏览；不要连接真实支付。');
  planWorkspace(root);
  assert.doesNotMatch(taskPlan(root).priorityTasks.map((item) => item.task).join('\n'), /(?:接入|启用|实现).{0,12}真实支付/);
});

test('an Xcode project without a test action gets a minimal validation bootstrap', () => {
  const task = validationBootstrapFor({
    platforms: ['iOS'],
    files: [{ path: 'HealthTrend.xcodeproj/project.pbxproj', searchText: '' }],
    goalIds: ['goal:health-authorization'],
    executionContext: sandbox
  });
  assert.match(task.action, /创建|修复/);
  assert.match(task.doneWhen, /xcodebuild test/);
});

test('an existing runnable Xcode test action is reused without bootstrap', () => {
  const task = validationBootstrapFor({
    platforms: ['iOS'],
    files: [{ path: 'HealthTrend.xcodeproj/xcshareddata/xcschemes/HealthTrend.xcscheme', searchText: '<TestAction><TestableReference /></TestAction>' }],
    goalIds: ['goal:health-authorization'],
    executionContext: sandbox
  });
  assert.equal(task, null);
});

test('validate-disabled execution context does not create test infrastructure', () => {
  const task = validationBootstrapFor({
    platforms: ['iOS'],
    files: [{ path: 'HealthTrend.xcodeproj/project.pbxproj', searchText: '' }],
    goalIds: ['goal:health-authorization'],
    executionContext: { allowPrepare: true, allowValidate: false }
  });
  assert.equal(task, null);
});

test('Node CLI does not receive an Xcode validation bootstrap', () => {
  const task = validationBootstrapFor({
    platforms: ['Node CLI'],
    files: [{ path: 'test/report.test.js', searchText: 'test' }],
    goalIds: ['goal:cli-json'],
    executionContext: sandbox
  });
  assert.equal(task, null);
});
