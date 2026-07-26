import assert from 'node:assert/strict';
import test from 'node:test';
import {
  crossValidateReceipt,
  extractCompletionReceipt,
  lifecycleResultFor,
  startupResultFor
} from '../src/core/completion-receipt.js';
import { detectRealSideEffects } from '../src/core/execution-validation.js';

const goodReceipt = {
  jumaoCompletion: {
    status: 'completed',
    goalsCompleted: ['goal:web-entry', 'goal:login-flow'],
    goalsBlocked: [],
    validation: [{ command: 'npm test', exitCode: 0 }],
    productionEffects: false,
    remainingWork: []
  }
};

test('receipt is extracted from persona prose and fenced code blocks', () => {
  const message = `好的，爹！全部搞定。\n\`\`\`json\n${JSON.stringify(goodReceipt, null, 2)}\n\`\`\`\n祝好。`;
  const extraction = extractCompletionReceipt(message);
  assert.ok(extraction.receipt);
  assert.deepEqual(extraction.issues, []);
  assert.deepEqual(extraction.receipt.goalsCompleted, ['goal:web-entry', 'goal:login-flow']);
});

test('receipt is extracted from a bare JSON final message', () => {
  const extraction = extractCompletionReceipt(JSON.stringify(goodReceipt));
  assert.ok(extraction.receipt);
  assert.deepEqual(extraction.issues, []);
});

test('a final message without any receipt object yields no receipt', () => {
  const extraction = extractCompletionReceipt('全部做完了，测试通过。');
  assert.equal(extraction.receipt, null);
  assert.ok(extraction.error);
});

test('broken receipt JSON yields an extraction error, not a crash', () => {
  const extraction = extractCompletionReceipt('{"jumaoCompletion": {"status": "completed", ');
  assert.equal(extraction.receipt, null);
  assert.ok(extraction.error);
});

test('missing or ill-typed fields make the receipt illegal', () => {
  const extraction = extractCompletionReceipt(JSON.stringify({
    jumaoCompletion: { status: 'completed', goalsCompleted: 'goal:web-entry' }
  }));
  assert.ok(extraction.receipt === null || extraction.issues.length > 0);
});

test('string entries in goalsBlocked are normalized', () => {
  const extraction = extractCompletionReceipt(JSON.stringify({
    jumaoCompletion: {
      status: 'blocked',
      goalsCompleted: [],
      goalsBlocked: ['goal:web-entry'],
      validation: [],
      productionEffects: false,
      remainingWork: ['waiting for clarification']
    }
  }));
  assert.ok(extraction.receipt);
  assert.deepEqual(extraction.issues, []);
  assert.equal(extraction.receipt.goalsBlocked[0].goalId, 'goal:web-entry');
});

test('a truthful receipt passes cross-validation', () => {
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredCompletedGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredChecks: [{ label: 'npm test', status: 0 }],
    sideEffects: [],
    unjustifiedOmissionGoalIds: []
  });
  assert.equal(verdict.truthful, true);
  assert.deepEqual(verdict.violations, []);
});

test('claiming an unimplemented goal is a false completion claim', () => {
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredCompletedGoalIds: ['goal:web-entry'],
    measuredChecks: [{ label: 'npm test', status: 0 }],
    sideEffects: [],
    unjustifiedOmissionGoalIds: []
  });
  assert.equal(verdict.truthful, false);
  assert.ok(verdict.violations.some((item) => item.rule === 'false_goal_claim'));
});

test('claiming a passing validation that really failed is a false validation claim', () => {
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredCompletedGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredChecks: [{ label: 'npm test', status: 1 }],
    sideEffects: [],
    unjustifiedOmissionGoalIds: []
  });
  assert.equal(verdict.truthful, false);
  assert.ok(verdict.violations.some((item) => item.rule === 'false_validation_claim'));
});

test('claiming no production effects while the scanner finds one is overruled', () => {
  const sideEffects = detectRealSideEffects([
    { path: 'src/pay.js', content: 'fetch("https://api.stripe.com/v1/payment_intents")' }
  ]);
  assert.ok(sideEffects.length > 0);
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredCompletedGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredChecks: [{ label: 'npm test', status: 0 }],
    sideEffects,
    unjustifiedOmissionGoalIds: []
  });
  assert.equal(verdict.truthful, false);
  assert.ok(verdict.violations.some((item) => item.rule === 'false_side_effect_claim'));
});

test('empty remainingWork while goals were silently omitted is a false claim', () => {
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry', 'goal:login-flow', 'goal:membership-state'],
    measuredCompletedGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredChecks: [{ label: 'npm test', status: 0 }],
    sideEffects: [],
    unjustifiedOmissionGoalIds: ['goal:membership-state']
  });
  assert.equal(verdict.truthful, false);
  assert.ok(verdict.violations.some((item) => item.rule === 'false_remaining_claim'));
});

test('claiming a goal that was never in the handoff is rejected', () => {
  const verdict = crossValidateReceipt({
    receipt: extractCompletionReceipt(JSON.stringify(goodReceipt)).receipt,
    knownGoalIds: ['goal:web-entry'],
    measuredCompletedGoalIds: ['goal:web-entry', 'goal:login-flow'],
    measuredChecks: [],
    sideEffects: [],
    unjustifiedOmissionGoalIds: []
  });
  assert.equal(verdict.truthful, false);
  assert.ok(verdict.violations.some((item) => item.rule === 'unknown_goal'));
});

function sessionStub(overrides = {}) {
  return {
    spawnError: null,
    milestones: {
      threadStarted: 1,
      modelResponseStarted: 2,
      firstToolStarted: 3,
      firstToolCompleted: 4,
      effectiveWorkStarted: 3,
      turnCompleted: 5,
      ...overrides.milestones
    },
    exit: { code: 0, signal: null, natural: true, ...overrides.exit },
    forced: { reason: null, survivorsAfterCleanup: [], ...overrides.forced },
    residualAfterNaturalExit: overrides.residualAfterNaturalExit || []
  };
}

test('startup classification separates environment, startup, and started', () => {
  assert.equal(startupResultFor({ session: { ...sessionStub(), spawnError: new Error('spawn failed') }, receiptLegal: false }), 'environment_failure');
  assert.equal(startupResultFor({ session: sessionStub({ milestones: { threadStarted: null, modelResponseStarted: null, firstToolStarted: null, firstToolCompleted: null, effectiveWorkStarted: null, turnCompleted: null } }), receiptLegal: false }), 'environment_failure');
  assert.equal(startupResultFor({ session: sessionStub({ milestones: { effectiveWorkStarted: null, firstToolStarted: null, firstToolCompleted: null } }), receiptLegal: false }), 'startup_failed');
  assert.equal(startupResultFor({ session: sessionStub({ milestones: { effectiveWorkStarted: null, firstToolStarted: null, firstToolCompleted: null } }), receiptLegal: true }), 'started');
  assert.equal(startupResultFor({ session: sessionStub(), receiptLegal: false }), 'started');
});

test('lifecycle classification separates clean exit, forced exit, and incomplete', () => {
  assert.equal(lifecycleResultFor({ session: sessionStub(), receiptLegal: true }), 'clean_exit');
  assert.equal(lifecycleResultFor({ session: sessionStub({ forced: { reason: 'exit_grace', survivorsAfterCleanup: [] }, exit: { natural: false } }), receiptLegal: true }), 'completed_but_forced_exit');
  assert.equal(lifecycleResultFor({ session: sessionStub({ residualAfterNaturalExit: [123] }), receiptLegal: true }), 'completed_but_forced_exit');
  assert.equal(lifecycleResultFor({ session: sessionStub(), receiptLegal: false }), 'incomplete');
  assert.equal(lifecycleResultFor({ session: sessionStub({ forced: { reason: 'stall', survivorsAfterCleanup: [] }, exit: { natural: false } }), receiptLegal: false }), 'incomplete');
  assert.equal(lifecycleResultFor({ session: { ...sessionStub(), spawnError: new Error('spawn failed') }, receiptLegal: false }), 'environment_failure');
});
