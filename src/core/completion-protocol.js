export const lifecycleTimeouts = Object.freeze({
  workMs: 15 * 60 * 1000,
  receiptExitGraceMs: 20 * 1000,
  childCleanupGraceMs: 10 * 1000
});

export function completionReceiptFor(value, expectedGoals = [], sideEffects = []) {
  const receipt = value && typeof value === 'object' ? value : null;
  const status = receipt?.status;
  const completed = unique(receipt?.goalsCompleted);
  const blocked = unique(receipt?.goalsBlocked);
  const validation = Array.isArray(receipt?.validation) ? receipt.validation : [];
  const remaining = Array.isArray(receipt?.remainingWork) ? receipt.remainingWork : null;
  const expected = unique(expectedGoals);
  const goalMatch = sameSet([...completed, ...blocked], expected);
  const validationValid = validation.length > 0 && validation.every((item) => typeof item?.command === 'string' && Number.isInteger(item.exitCode));
  const statusValid = status === 'completed' || status === 'validation_failed';
  const productionSafe = receipt?.productionEffects === false && sideEffects.length === 0;
  const valid = statusValid && goalMatch && validationValid && Array.isArray(remaining) && productionSafe;
  return {
    valid,
    receipt,
    deliveryResult: valid && status === 'completed' && validation.every((item) => item.exitCode === 0) && remaining.length === 0 ? 'passed' : 'failed',
    issues: [
      !statusValid && 'invalid_status',
      !goalMatch && 'goal_mismatch',
      !validationValid && 'invalid_validation',
      !Array.isArray(remaining) && 'missing_remaining_work',
      !productionSafe && 'production_effect_detected'
    ].filter(Boolean)
  };
}

export function lifecycleResultFor({ receipt, processExited = false, forcedCleanup = false, childProcessesAlive = false, waitingForInput = false } = {}) {
  if (!receipt?.valid || waitingForInput) return 'incomplete';
  if (forcedCleanup || childProcessesAlive || !processExited) return 'completed_but_forced_exit';
  return 'clean_exit';
}

export class CompletionLifecycle {
  constructor() {
    this.state = 'running';
    this.receipt = null;
    this.activeTool = null;
    this.processExited = false;
    this.forced = false;
    this.childrenAlive = false;
  }

  toolRunning(name) { this.activeTool = name; return this; }
  toolFinished() { this.activeTool = null; return this; }
  received(receipt) { this.receipt = receipt; this.state = 'completion_received'; return this; }
  exited({ childrenAlive = false } = {}) { this.processExited = true; this.childrenAlive = childrenAlive; this.state = 'process_exited'; return this; }
  forcedCleanup() { this.forced = true; this.state = 'cleanup_complete'; return this; }
  timedOut() { return this; }
  canCleanup() { return Boolean(this.receipt?.valid) && !this.activeTool; }
  result() { return lifecycleResultFor({ receipt: this.receipt, processExited: this.processExited, forcedCleanup: this.forced, childProcessesAlive: this.childrenAlive }); }
}

export function runCompletionSession({ binary, args, cwd, receiptFile, expectedGoals, timeout = lifecycleTimeouts, validateReceipt }) {
  return new Promise((resolve) => {
    const lifecycle = new CompletionLifecycle();
    const child = spawn(binary, args, { cwd, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let receipt = null;
    let receiptTimer = null;
    let cleanupTimer = null;
    let workTimer = null;
    let forcedCleanup = false;
    const readReceipt = () => {
      if (receipt || !fs.existsSync(receiptFile)) return;
      try {
        receipt = validateReceipt(JSON.parse(fs.readFileSync(receiptFile, 'utf8')), expectedGoals);
        lifecycle.received(receipt);
        child.stdin.end();
        receiptTimer = setTimeout(() => terminate('SIGTERM'), timeout.receiptExitGraceMs);
      } catch {
        receipt = completionReceiptFor(null, expectedGoals, []);
      }
    };
    const terminate = (signal) => {
      if (child.exitCode !== null || child.signalCode !== null) return;
      forcedCleanup = true;
      lifecycle.forcedCleanup();
      try { process.kill(-child.pid, signal); } catch { try { child.kill(signal); } catch {} }
      if (signal === 'SIGTERM') cleanupTimer = setTimeout(() => terminate('SIGKILL'), timeout.childCleanupGraceMs);
    };
    const finalize = (code, signal) => {
      readReceipt();
      clearInterval(poll);
      clearTimeout(receiptTimer);
      clearTimeout(cleanupTimer);
      clearTimeout(workTimer);
      lifecycle.exited();
      resolve({
        status: code,
        signal: signal || null,
        stdout,
        stderr,
        receipt,
        lifecycleResult: lifecycleResultFor({ receipt, processExited: true, forcedCleanup }),
        forcedCleanup,
        state: lifecycle.state
      });
    };
    child.stdout.on('data', (chunk) => { stdout += chunk; readReceipt(); });
    child.stderr.on('data', (chunk) => { stderr += chunk; readReceipt(); });
    child.on('error', (error) => { stderr += `${error.message}\n`; });
    child.on('exit', finalize);
    const poll = setInterval(readReceipt, 50);
    workTimer = setTimeout(() => { lifecycle.timedOut(); terminate('SIGTERM'); }, timeout.workMs);
  });
}

function unique(value) { return [...new Set(Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [])]; }
function sameSet(left, right) { return left.length === right.length && left.every((item) => right.includes(item)); }
import fs from 'node:fs';
import { spawn } from 'node:child_process';
