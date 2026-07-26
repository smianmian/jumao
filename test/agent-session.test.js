import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { killProcessGroup, runAgentSession } from '../src/core/agent-session.js';
import { extractCompletionReceipt, lifecycleResultFor, startupResultFor } from '../src/core/completion-receipt.js';

const fakeAgent = fileURLToPath(new URL('./fixtures/fake-coding-agent.js', import.meta.url));

const fastTimeouts = {
  startupMs: 700,
  stallMs: 900,
  exitGraceMs: 400,
  globalMs: 4000,
  termGraceMs: 250,
  tickMs: 25
};

function tempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function runScenario(scenario, { timeouts = {}, env = {}, workDir = null } = {}) {
  const evidenceDir = tempDir('jumao-session-evidence-');
  const cwd = workDir || tempDir('jumao-session-work-');
  return runAgentSession({
    command: process.execPath,
    args: [fakeAgent],
    cwd,
    env: { ...process.env, FAKE_AGENT_SCENARIO: scenario, FAKE_AGENT_WORKDIR: cwd, ...env },
    evidenceDir,
    timeouts: { ...fastTimeouts, ...timeouts }
  }).then((session) => ({ session, evidenceDir, cwd }));
}

function receiptLegalFor(session) {
  const extraction = extractCompletionReceipt(session.finalMessage || '');
  return Boolean(extraction.receipt) && extraction.issues.length === 0;
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

test('scenario: normal completion emits receipt and exits naturally', async () => {
  const { session, evidenceDir } = await runScenario('complete_and_exit');
  assert.equal(session.exit.natural, true);
  assert.equal(session.exit.code, 0);
  assert.equal(session.forced.reason, null);
  assert.deepEqual(session.residualAfterNaturalExit, []);
  assert.ok(session.milestones.threadStarted);
  assert.ok(session.milestones.firstToolStarted);
  assert.ok(session.milestones.firstToolCompleted);
  assert.ok(session.milestones.effectiveWorkStarted);
  assert.ok(session.milestones.turnCompleted);
  assert.ok(session.finalMessage.includes('jumaoCompletion'));
  const legal = receiptLegalFor(session);
  assert.equal(legal, true);
  assert.equal(startupResultFor({ session, receiptLegal: legal }), 'started');
  assert.equal(lifecycleResultFor({ session, receiptLegal: legal }), 'clean_exit');
  for (const file of ['events.jsonl', 'stderr.log', 'timeline.json']) {
    assert.ok(fs.existsSync(path.join(evidenceDir, file)), `missing ${file}`);
  }
});

test('scenario: receipt produced but process refuses to exit', async () => {
  const { session } = await runScenario('receipt_then_hang');
  assert.equal(session.exit.natural, false);
  assert.equal(session.forced.reason, 'exit_grace');
  assert.deepEqual(session.forced.survivorsAfterCleanup, []);
  const legal = receiptLegalFor(session);
  assert.equal(legal, true);
  assert.equal(lifecycleResultFor({ session, receiptLegal: legal }), 'completed_but_forced_exit');
});

test('scenario: work done but no receipt in the final message', async () => {
  const { session, cwd } = await runScenario('work_no_receipt');
  assert.equal(session.exit.natural, true);
  assert.ok(fs.existsSync(path.join(cwd, 'modified-by-agent.txt')));
  const extraction = extractCompletionReceipt(session.finalMessage || '');
  assert.equal(extraction.receipt, null);
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'incomplete');
});

test('scenario: malformed receipt is illegal, never a crash', async () => {
  const { session } = await runScenario('malformed_receipt');
  const extraction = extractCompletionReceipt(session.finalMessage || '');
  assert.equal(extraction.receipt, null);
  assert.ok(extraction.error);
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'incomplete');
});

test('scenario: an agent waiting for stdin EOF is unblocked because stdin is closed at spawn', async () => {
  const { session } = await runScenario('wait_stdin_then_complete');
  assert.equal(session.exit.natural, true);
  assert.equal(session.forced.reason, null);
  const legal = receiptLegalFor(session);
  assert.equal(lifecycleResultFor({ session, receiptLegal: legal }), 'clean_exit');
});

test('scenario: agent that never starts effective work is a startup failure', async () => {
  const { session } = await runScenario('never_start');
  assert.equal(session.forced.reason, 'startup_timeout');
  assert.equal(startupResultFor({ session, receiptLegal: false }), 'startup_failed');
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'incomplete');
  assert.deepEqual(session.forced.survivorsAfterCleanup, []);
});

test('scenario: hung first tool call stalls and is cleaned with its children', async () => {
  const { session, cwd } = await runScenario('tool_hang_with_child', { timeouts: { stallMs: 600 } });
  assert.equal(session.forced.reason, 'stall');
  assert.ok(session.milestones.effectiveWorkStarted, 'tool start counts as effective work');
  assert.equal(startupResultFor({ session, receiptLegal: false }), 'started');
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'incomplete');
  assert.deepEqual(session.forced.survivorsAfterCleanup, []);
  const pidFile = path.join(cwd, 'fake-agent-child.pid');
  assert.ok(fs.existsSync(pidFile));
  const childPid = Number(fs.readFileSync(pidFile, 'utf8'));
  assert.equal(alive(childPid), false, 'leaked grandchild must be terminated with the group');
});

test('scenario: a long quiet tool under the stall budget completes cleanly (npm test / xcodebuild class)', async () => {
  const { session } = await runScenario('slow_tool_completes', {
    timeouts: { stallMs: 1500 },
    env: { FAKE_AGENT_TOOL_MS: '600' }
  });
  assert.equal(session.exit.natural, true);
  assert.equal(session.forced.reason, null);
  const legal = receiptLegalFor(session);
  assert.equal(lifecycleResultFor({ session, receiptLegal: legal }), 'clean_exit');
});

test('scenario: natural exit with a leaked child is detected and cleaned', async () => {
  const { session, cwd } = await runScenario('leak_child');
  assert.equal(session.exit.natural, true);
  assert.ok(session.residualAfterNaturalExit.length > 0, 'residual child must be reported');
  const legal = receiptLegalFor(session);
  assert.equal(legal, true);
  assert.equal(lifecycleResultFor({ session, receiptLegal: legal }), 'completed_but_forced_exit');
  const childPid = Number(fs.readFileSync(path.join(cwd, 'fake-agent-child.pid'), 'utf8'));
  assert.equal(alive(childPid), false, 'residual child must be terminated');
});

test('scenario: endless event activity is stopped by the global timeout only', async () => {
  const { session } = await runScenario('event_drip_forever', { timeouts: { globalMs: 1500, stallMs: 1200 } });
  assert.equal(session.forced.reason, 'global_timeout');
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'incomplete');
});

test('scenario: spawn failure is an environment failure, not a receipt failure', async () => {
  const evidenceDir = tempDir('jumao-session-evidence-');
  const session = await runAgentSession({
    command: path.join(evidenceDir, 'definitely-not-a-binary'),
    args: [],
    cwd: evidenceDir,
    env: process.env,
    evidenceDir,
    timeouts: fastTimeouts
  });
  assert.ok(session.spawnError);
  assert.equal(startupResultFor({ session, receiptLegal: false }), 'environment_failure');
  assert.equal(lifecycleResultFor({ session, receiptLegal: false }), 'environment_failure');
});

test('cleanup of an already-exited group is a recorded no-op, never an error', async () => {
  const child = spawn(process.execPath, ['-e', 'process.exit(0)'], { detached: true, stdio: 'ignore' });
  const pid = child.pid;
  await new Promise((resolve) => child.on('exit', resolve));
  const outcome = await killProcessGroup({ pgid: pid, termGraceMs: 50 });
  assert.equal(outcome.noop, true);
  assert.deepEqual(outcome.survivors, []);
});

test('controlled cleanup never touches processes outside the session group', async () => {
  const bystander = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000);'], { detached: true, stdio: 'ignore' });
  bystander.unref();
  try {
    const { session } = await runScenario('tool_hang', { timeouts: { stallMs: 500 } });
    assert.equal(session.forced.reason, 'stall');
    assert.equal(alive(bystander.pid), true, 'unrelated detached process must survive cleanup');
  } finally {
    try { process.kill(bystander.pid, 'SIGKILL'); } catch { /* already gone */ }
  }
});
