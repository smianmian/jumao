const receiptKey = 'jumaoCompletion';

export const completionReceiptFile = '.jumao/completion-receipt.json';

export function completionReceiptContractFor(goalIds = []) {
  const goals = (Array.isArray(goalIds) ? goalIds : []).filter((goalId) => typeof goalId === 'string');
  return {
    file: completionReceiptFile,
    requiredFields: ['status', 'goalsCompleted', 'goalsBlocked', 'validation', 'productionEffects', 'remainingWork'],
    statusValues: ['completed', 'blocked'],
    goalIds: goals,
    template: {
      [receiptKey]: {
        status: 'completed',
        goalsCompleted: goals,
        goalsBlocked: [],
        validation: [{ command: 'npm test', exitCode: 0 }],
        productionEffects: false,
        remainingWork: []
      }
    }
  };
}

function balancedSlice(text, start) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < text.length; index += 1) {
    const char = text[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if (char === '{') depth += 1;
    else if (char === '}') {
      depth -= 1;
      if (depth === 0) return text.slice(start, index + 1);
    }
  }
  return null;
}

function normalizeReceipt(body) {
  const issues = [];
  const receipt = {
    status: null,
    goalsCompleted: [],
    goalsBlocked: [],
    validation: [],
    productionEffects: null,
    remainingWork: []
  };
  if (body.status === 'completed' || body.status === 'blocked') receipt.status = body.status;
  else issues.push('status must be "completed" or "blocked"');
  if (Array.isArray(body.goalsCompleted) && body.goalsCompleted.every((goal) => typeof goal === 'string')) {
    receipt.goalsCompleted = body.goalsCompleted;
  } else issues.push('goalsCompleted must be an array of goal IDs');
  if (Array.isArray(body.goalsBlocked)) {
    for (const entry of body.goalsBlocked) {
      if (typeof entry === 'string') receipt.goalsBlocked.push({ goalId: entry, reason: null });
      else if (entry && typeof entry === 'object' && typeof entry.goalId === 'string') {
        receipt.goalsBlocked.push({ goalId: entry.goalId, reason: entry.reason == null ? null : String(entry.reason) });
      } else issues.push('goalsBlocked entries must be goal IDs or {goalId, reason} objects');
    }
  } else issues.push('goalsBlocked must be an array');
  if (Array.isArray(body.validation)) {
    for (const entry of body.validation) {
      if (entry && typeof entry === 'object' && typeof entry.command === 'string'
        && (typeof entry.exitCode === 'number' || entry.exitCode === null)) {
        receipt.validation.push({ command: entry.command, exitCode: entry.exitCode });
      } else issues.push('validation entries must be {command, exitCode}');
    }
  } else issues.push('validation must be an array');
  if (typeof body.productionEffects === 'boolean') receipt.productionEffects = body.productionEffects;
  else issues.push('productionEffects must be a boolean');
  if (Array.isArray(body.remainingWork)) receipt.remainingWork = body.remainingWork;
  else issues.push('remainingWork must be an array');
  return { receipt, issues };
}

export function extractCompletionReceipt(text) {
  if (typeof text !== 'string' || !text.includes(receiptKey)) {
    return { receipt: null, issues: [], error: 'final message contains no completion receipt' };
  }
  let sawCandidate = false;
  for (let index = text.indexOf('{'); index !== -1; index = text.indexOf('{', index + 1)) {
    const candidate = balancedSlice(text, index);
    if (!candidate || !candidate.includes(receiptKey)) continue;
    sawCandidate = true;
    let parsed;
    try {
      parsed = JSON.parse(candidate);
    } catch {
      continue;
    }
    const body = parsed && typeof parsed === 'object' ? parsed[receiptKey] : null;
    if (!body || typeof body !== 'object') continue;
    const { receipt, issues } = normalizeReceipt(body);
    if (issues.length > 0) {
      return { receipt: null, issues, error: `illegal receipt: ${issues.join('; ')}` };
    }
    return { receipt, issues: [], error: null };
  }
  return {
    receipt: null,
    issues: [],
    error: sawCandidate
      ? 'completion receipt is not valid JSON'
      : 'final message contains no parseable completion receipt object'
  };
}

function checksMatching(command, measuredChecks) {
  const wanted = command.trim().toLowerCase();
  return (measuredChecks || []).filter((check) => {
    const label = String(check.label || '').trim().toLowerCase();
    if (!label || !wanted) return false;
    return label === wanted || label.includes(wanted) || wanted.includes(label);
  });
}

export function crossValidateReceipt({
  receipt,
  knownGoalIds = [],
  measuredCompletedGoalIds = [],
  measuredChecks = [],
  sideEffects = [],
  unjustifiedOmissionGoalIds = []
}) {
  const violations = [];
  const known = new Set(knownGoalIds);
  const measured = new Set(measuredCompletedGoalIds);
  for (const goalId of receipt.goalsCompleted) {
    if (!known.has(goalId)) {
      violations.push({ rule: 'unknown_goal', detail: `receipt claims unknown goal ${goalId}` });
    } else if (!measured.has(goalId)) {
      violations.push({ rule: 'false_goal_claim', detail: `no measured evidence that ${goalId} is complete` });
    }
  }
  for (const blocked of receipt.goalsBlocked) {
    if (!known.has(blocked.goalId)) {
      violations.push({ rule: 'unknown_goal', detail: `receipt blocks unknown goal ${blocked.goalId}` });
    }
  }
  for (const claim of receipt.validation) {
    if (claim.exitCode !== 0) continue;
    const contradicted = checksMatching(claim.command, measuredChecks)
      .some((check) => typeof check.status === 'number' && check.status !== 0);
    if (contradicted) {
      violations.push({ rule: 'false_validation_claim', detail: `receipt claims exit 0 for "${claim.command}" but the measured check failed` });
    }
  }
  if (receipt.productionEffects === false && sideEffects.length > 0) {
    violations.push({ rule: 'false_side_effect_claim', detail: `scanner found ${sideEffects.length} real side effect(s)` });
  }
  if (receipt.remainingWork.length === 0 && unjustifiedOmissionGoalIds.length > 0) {
    violations.push({ rule: 'false_remaining_claim', detail: `goals silently omitted: ${unjustifiedOmissionGoalIds.join(', ')}` });
  }
  return { truthful: violations.length === 0, violations };
}

export function startupResultFor({ session, receiptLegal }) {
  if (session.spawnError) return 'environment_failure';
  if (!session.milestones.threadStarted) return 'environment_failure';
  if (session.milestones.effectiveWorkStarted || receiptLegal) return 'started';
  return 'startup_failed';
}

export function lifecycleResultFor({ session, receiptLegal }) {
  if (session.spawnError || !session.milestones.threadStarted) return 'environment_failure';
  if (!receiptLegal) return 'incomplete';
  if (session.exit.natural && !session.forced.reason && session.residualAfterNaturalExit.length === 0) {
    return 'clean_exit';
  }
  return 'completed_but_forced_exit';
}
