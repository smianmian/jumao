import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { planWorkspace } from '../src/core/planning-runtime.js';
import { completionReceiptContractFor, completionReceiptFile } from '../src/core/completion-receipt.js';
import { completionReceiptStage, readJumaoStatus, renderStatus } from '../src/core/status.js';

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-receipt-prod-test-'));
}

function write(root, relativePath, content) {
  const output = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content, 'utf8');
}

function plannedWorkspace() {
  const root = workspace();
  write(root, 'package.json', `${JSON.stringify({ name: 'demo', private: true, type: 'module', scripts: { test: 'node --test' } }, null, 2)}\n`);
  write(root, 'src/catalog.js', 'export const listProducts = () => [];\n');
  write(root, 'test/catalog.test.js', 'import test from "node:test";\ntest("catalog", () => {});\n');
  write(root, '.jumao/intake-answers.json', `${JSON.stringify({
    schemaVersion: 1,
    mode: 'existing_project',
    answers: { requestedChange: '为现有网页目录增加邮箱登录，保留匿名浏览；不要接真实支付。' },
    updatedAt: new Date().toISOString()
  }, null, 2)}\n`);
  planWorkspace(root);
  return root;
}

function latestTaskPlan(root) {
  const latest = JSON.parse(fs.readFileSync(path.join(root, '.jumao', 'latest-run.json'), 'utf8'));
  return JSON.parse(fs.readFileSync(path.join(root, latest.runPath, 'task-plan.json'), 'utf8'));
}

test('completion receipt contract exposes file, fields, and template', () => {
  const contract = completionReceiptContractFor(['goal:login-flow', 'goal:anonymous-browsing']);
  assert.equal(contract.file, '.jumao/completion-receipt.json');
  assert.deepEqual(contract.statusValues, ['completed', 'blocked']);
  assert.deepEqual(contract.template.jumaoCompletion.goalsCompleted, ['goal:login-flow', 'goal:anonymous-browsing']);
  assert.equal(contract.template.jumaoCompletion.productionEffects, false);
});

test('jumao plan output carries the completion receipt contract for real users', () => {
  const root = plannedWorkspace();
  const taskPlan = latestTaskPlan(root);
  assert.ok(taskPlan.completionReceipt, 'task-plan.json must include completionReceipt');
  assert.equal(taskPlan.completionReceipt.file, completionReceiptFile);
  assert.ok(taskPlan.completionReceipt.goalIds.length > 0, 'contract lists the explicit goal IDs');
  assert.ok(taskPlan.codexInstructions.some((line) => line.includes('completion-receipt.json')));
  assert.ok(taskPlan.codexInstructions.some((line) => line.includes('停止调用工具')));
  const markdown = fs.readFileSync(path.join(root, 'tasks', 'jumao-agent-plan.md'), 'utf8');
  assert.ok(markdown.includes('## 11. 完成回执要求'));
  assert.ok(markdown.includes('jumaoCompletion'));
});

test('a completed receipt file surfaces a plain-language stage', () => {
  const root = plannedWorkspace();
  write(root, completionReceiptFile, `${JSON.stringify({
    jumaoCompletion: {
      status: 'completed',
      goalsCompleted: ['goal:login-flow'],
      goalsBlocked: [],
      validation: [{ command: 'npm test', exitCode: 0 }],
      productionEffects: false,
      remainingWork: []
    }
  }, null, 2)}\n`);
  const stage = completionReceiptStage(root);
  assert.equal(stage.stage, 'receipt_completed');
  assert.ok(stage.message.includes('不是'), 'message keeps the X。不是 Y。 anti-overpromise form');
  const status = readJumaoStatus(root);
  assert.equal(status.completionReceipt.stage, 'receipt_completed');
  const rendered = renderStatus(status);
  assert.ok(rendered.includes('回执：'));
  assert.ok(rendered.includes(stage.nextSafeTask));
});

test('a bare receipt without the jumaoCompletion wrapper is tolerated', () => {
  const root = plannedWorkspace();
  write(root, completionReceiptFile, `${JSON.stringify({
    status: 'completed',
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  }, null, 2)}\n`);
  assert.equal(completionReceiptStage(root).stage, 'receipt_completed');
});

test('a blocked receipt surfaces the blocked stage, not a failure', () => {
  const root = plannedWorkspace();
  write(root, completionReceiptFile, `${JSON.stringify({
    jumaoCompletion: {
      status: 'blocked',
      goalsCompleted: [],
      goalsBlocked: [{ goalId: 'goal:login-flow', reason: '缺少登录范围确认' }],
      validation: [],
      productionEffects: false,
      remainingWork: ['等待确认']
    }
  }, null, 2)}\n`);
  const stage = completionReceiptStage(root);
  assert.equal(stage.stage, 'receipt_blocked');
  assert.ok(stage.message.includes('不是失败'));
});

test('a malformed receipt file surfaces the invalid stage without crashing', () => {
  const root = plannedWorkspace();
  write(root, completionReceiptFile, '{"jumaoCompletion": {"status": "completed", ');
  const stage = completionReceiptStage(root);
  assert.equal(stage.stage, 'receipt_invalid');
  assert.equal(stage.receipt, null);
});

test('no receipt file means no receipt stage', () => {
  const root = plannedWorkspace();
  assert.equal(completionReceiptStage(root), null);
  assert.equal(readJumaoStatus(root).completionReceipt, undefined);
});
