import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { verifyWorkspaceReceipt, renderVerifyReport } from '../src/core/verify.js';

const repoRoot = path.resolve(new URL('..', import.meta.url).pathname);
const cli = path.join(repoRoot, 'bin', 'jumao.js');

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-verify-test-'));
}

function write(root, relativePath, content) {
  const output = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content, 'utf8');
}

function git(root, ...args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
}

function initGit(root) {
  git(root, 'init', '-q');
  git(root, 'config', 'user.email', 'verify@example.test');
  git(root, 'config', 'user.name', 'Verify');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'baseline', '--allow-empty');
}

function writeRun(root, goalCoverage) {
  const runPath = '.jumao/runs/run-1';
  write(root, '.jumao/latest-run.json', JSON.stringify({ runId: 'run-1', runPath }));
  write(root, path.posix.join(runPath, 'task-plan.json'), JSON.stringify({ goalCoverage }));
}

function writeReceipt(root, body) {
  write(root, '.jumao/completion-receipt.json', JSON.stringify({ jumaoCompletion: body }, null, 2));
}

const cliGoal = [{ goalId: 'goal:cli-json', label: '--json 输出', status: 'covered' }];

test('verify reports a missing receipt in plain language', () => {
  const root = workspace();
  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'no_receipt');
  assert.match(result.message, /还没有 AI 交回的完成回执/);
});

test('verify flags an illegal receipt file', () => {
  const root = workspace();
  write(root, '.jumao/completion-receipt.json', JSON.stringify({ jumaoCompletion: { status: 'done' } }));
  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'illegal');
  assert.match(result.message, /不完整或格式不对/);
});

test('verify trusts a truthful receipt backed by changed-file evidence and passing checks', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module', scripts: { test: 'node --test' } }));
  write(root, 'bin/report.js', 'console.log("items: 0");\n');
  write(root, 'test/report.test.js', 'import test from "node:test";\ntest("ok", () => {});\n');
  initGit(root);
  write(root, 'bin/report.js', 'const json = process.argv.includes("--json");\nconsole.log(json ? JSON.stringify({ items: 0 }) : "items: 0");\n');
  writeRun(root, cliGoal);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: ['goal:cli-json'],
    goalsBlocked: [],
    validation: [{ command: 'npm test', exitCode: 0 }],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'trusted', JSON.stringify(result.violations));
  assert.deepEqual(result.violations, []);
  assert.match(result.message, /对得上/);
  assert.ok(result.measuredChecks.some((check) => check.label === 'npm test' && check.status === 0));
});

test('verify catches a false goal claim', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module' }));
  write(root, 'src/other.js', 'export const x = 1;\n');
  initGit(root);
  write(root, 'src/other.js', 'export const x = 2;\n');
  writeRun(root, cliGoal);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: ['goal:cli-json'],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'untrusted');
  assert.ok(result.violations.some((violation) => violation.rule === 'false_goal_claim'));
});

test('verify catches a false validation claim by re-running the project checks', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module', scripts: { test: 'node -e "process.exit(1)"' } }));
  initGit(root);
  writeRun(root, []);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [{ command: 'npm test', exitCode: 0 }],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'untrusted');
  assert.ok(result.violations.some((violation) => violation.rule === 'false_validation_claim'));
});

test('verify catches a false no-side-effect claim with the scanner', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module' }));
  initGit(root);
  write(root, 'src/pay.js', 'fetch("https://api.stripe.com/v1/charges", { method: "POST" });\n');
  writeRun(root, []);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'untrusted');
  assert.ok(result.violations.some((violation) => violation.rule === 'false_side_effect_claim'));
});

test('verify catches silently omitted goals', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module' }));
  initGit(root);
  writeRun(root, [
    { goalId: 'goal:cli-json', label: '--json 输出', status: 'covered' },
    { goalId: 'goal:cli-text-compatibility', label: '保留文本输出', status: 'covered' }
  ]);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'untrusted');
  assert.ok(result.violations.some((violation) => violation.rule === 'false_remaining_claim'));
});

test('verify without git reports limits instead of false accusations', () => {
  const root = workspace();
  writeRun(root, cliGoal);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: ['goal:cli-json'],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  });

  const result = verifyWorkspaceReceipt(root);
  assert.equal(result.state, 'trusted_with_limits');
  assert.ok(result.limits.some((limit) => limit.includes('git')));
  assert.deepEqual(result.violations, []);
});

test('verify report and CLI exit codes stay plain and machine-readable', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'demo', type: 'module' }));
  initGit(root);
  writeRun(root, []);
  writeReceipt(root, {
    status: 'completed',
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [],
    productionEffects: false,
    remainingWork: []
  });

  const text = spawnSync(process.execPath, [cli, 'verify', root], { encoding: 'utf8' });
  assert.equal(text.status, 0, text.stdout + text.stderr);
  assert.match(text.stdout, /橘猫回执核验/);
  assert.doesNotMatch(text.stdout, /crossValidate|goalId|unknown_goal/);

  const json = spawnSync(process.execPath, [cli, 'verify', root, '--json'], { encoding: 'utf8' });
  assert.equal(json.status, 0);
  const parsed = JSON.parse(json.stdout);
  assert.ok(['trusted', 'trusted_with_limits'].includes(parsed.state));

  const rendered = renderVerifyReport(verifyWorkspaceReceipt(root));
  assert.match(rendered, /橘猫没法独立核对的部分/);
});
