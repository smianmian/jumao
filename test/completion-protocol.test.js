import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  completionReceiptFor,
  lifecycleResultFor,
  CompletionLifecycle,
  runCompletionSession
} from '../src/core/completion-protocol.js';

const goals = ['goal:a', 'goal:b'];
const completed = { status: 'completed', goalsCompleted: goals, goalsBlocked: [], validation: [{ command: 'npm test', exitCode: 0 }], productionEffects: false, remainingWork: [] };

test('valid receipt and natural exit is clean', () => {
  const receipt = completionReceiptFor(completed, goals, []);
  assert.equal(receipt.valid, true);
  assert.equal(lifecycleResultFor({ receipt, processExited: true, forcedCleanup: false }), 'clean_exit');
});

test('receipt followed by forced process cleanup is completed but forced', () => {
  const receipt = completionReceiptFor(completed, goals, []);
  const lifecycle = new CompletionLifecycle();
  lifecycle.received(receipt).forcedCleanup();
  assert.equal(lifecycle.result(), 'completed_but_forced_exit');
});

test('file changes without receipt are not successful', () => {
  assert.equal(lifecycleResultFor({ receipt: null, processExited: true, forcedCleanup: false }), 'incomplete');
});

test('validation_failed receipt preserves failure', () => {
  const receipt = completionReceiptFor({ ...completed, status: 'validation_failed', validation: [{ command: 'npm test', exitCode: 1 }] }, goals, []);
  assert.equal(receipt.valid, true);
  assert.equal(receipt.deliveryResult, 'failed');
});

test('waiting for input is classified without replying', () => {
  assert.equal(lifecycleResultFor({ waitingForInput: true }), 'incomplete');
});

test('running validation prevents cleanup', () => {
  const lifecycle = new CompletionLifecycle();
  lifecycle.toolRunning('xcodebuild test');
  assert.equal(lifecycle.canCleanup(), false);
  lifecycle.toolFinished();
  assert.equal(lifecycle.canCleanup(), false);
});

test('npm test running also prevents cleanup', () => {
  const lifecycle = new CompletionLifecycle();
  lifecycle.toolRunning('npm test');
  assert.equal(lifecycle.canCleanup(), false);
});

test('exited process with surviving session child requires cleanup', () => {
  const receipt = completionReceiptFor(completed, goals, []);
  assert.equal(lifecycleResultFor({ receipt, processExited: true, childProcessesAlive: true }), 'completed_but_forced_exit');
});

test('malformed receipt is rejected', () => {
  assert.equal(completionReceiptFor({ status: 'completed' }, goals, []).valid, false);
});

test('scanner violation defeats self-reported no production effect', () => {
  assert.equal(completionReceiptFor(completed, goals, ['real_payment: src/pay.js']).valid, false);
});

test('receipt goal list must match expected coverage', () => {
  assert.equal(completionReceiptFor({ ...completed, goalsCompleted: ['goal:a'] }, goals, []).valid, false);
});

test('global timeout is incomplete without receipt and preserves state', () => {
  const lifecycle = new CompletionLifecycle();
  lifecycle.timedOut();
  assert.equal(lifecycle.result(), 'incomplete');
  assert.equal(lifecycle.state, 'running');
});

test('fake Codex receipt closes stdin and exits cleanly', async () => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-completion-'));
  const file = path.join(cwd, 'completion-receipt.json');
  const script = `require('fs').writeFileSync(${JSON.stringify(file)}, ${JSON.stringify(JSON.stringify(completed))});`;
  const result = await runCompletionSession({ binary: process.execPath, args: ['-e', script], cwd, receiptFile: file, expectedGoals: goals, validateReceipt: (value, ids) => completionReceiptFor(value, ids, []) });
  assert.equal(result.lifecycleResult, 'clean_exit');
  assert.equal(result.receipt.valid, true);
});
