#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { benchmarkCases } from './cases.js';
import { adversarialCases } from './adversarial-cases.js';
import { executionHandoffForPlan, sandboxExecutionContext } from '../src/core/execution-handoff.js';
import { detectRealSideEffects } from '../src/core/execution-validation.js';
import { completionReceiptFor, lifecycleTimeouts, runCompletionSession } from '../src/core/completion-protocol.js';

const repoRoot = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const resultsRoot = process.env.RESULTS_DIR
  ? path.resolve(process.env.RESULTS_DIR)
  : path.join(repoRoot, 'benchmark', 'results', 'executable-goal-validation');
const baselineRef = process.env.BASELINE_REF || '3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567';
const repairRef = process.env.REPAIR_REF || 'HEAD';
const repetitions = Number(process.env.REPETITIONS || 3);
const targetIds = ['saas-web-membership', 'high-risk-health-data', 'existing-node-cli-refactor'];
const executionContext = sandboxExecutionContext(['current temporary worktree']);
const executionPrompt = [
  'Implement only the requested change using the supplied Jumao plan.',
  'Preserve all stated constraints and work in this temporary project only.',
  'This is a sandbox_implementation handoff. The current request authorizes prepare and validate in the current worktree.',
  'Do not ask for another owner confirmation before ordinary local code changes.',
  'Do not execute production effects: do not touch real accounts, real data, production environments, real health data, payments, or external paid services.',
  'If the plan mentions an execute phase that is blocked, continue all allowed prepare and validate work and report the blocked boundary.',
  'Read execution-handoff.json. Every core goal must satisfy its listed action, target, and doneWhen; create a local Web entry or test target when that handoff requires one.',
  'After finishing allowed implementation and validation, write exactly one JSON Completion Receipt to completion-receipt.json using the handoff fields. Include real commands and exit codes; use validation_failed if any validation failed. After writing it, stop calling tools, do not wait for input, and end this one-shot session.',
  'Do not commit. Run the project tests and report commands, modified files, unmet goals, invalid changes, constraint violations, human interventions, and rework loops.',
  `Execution context (session-only, not a project authorization): ${JSON.stringify(executionContext)}`
].join('\n');

function writeJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value, 'utf8');
}

function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function command(binary, args, cwd, options = {}) {
  const result = spawnSync(binary, args, {
    cwd,
    encoding: 'utf8',
    timeout: options.timeout || 240000,
    killSignal: options.killSignal || 'SIGKILL',
    maxBuffer: 16 * 1024 * 1024,
    env: options.env || process.env
  });
  return {
    command: [binary, ...args].join(' '),
    status: result.status,
    signal: result.signal || null,
    timedOut: Boolean(result.error && result.error.code === 'ETIMEDOUT'),
    stdout: result.stdout || '',
    stderr: result.stderr || ''
  };
}

function mustCommand(binary, args, cwd) {
  const result = command(binary, args, cwd);
  if (result.status !== 0) throw new Error(`${result.command}\n${result.stderr || result.stdout}`);
  return result;
}

function materialize(root, benchmarkCase) {
  for (const [relativePath, content] of Object.entries(benchmarkCase.files)) {
    const output = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, content, 'utf8');
  }
}

function fixtureFingerprint(benchmarkCase) {
  const lines = Object.entries(benchmarkCase.files)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([relativePath, content]) => `${relativePath}:${crypto.createHash('sha256').update(content).digest('hex')}`);
  return crypto.createHash('sha256').update(lines.join('\n')).digest('hex');
}

function initializeFixture(root) {
  mustCommand('git', ['init', '-q'], root);
  mustCommand('git', ['config', 'user.email', 'benchmark@example.test'], root);
  mustCommand('git', ['config', 'user.name', 'Benchmark'], root);
  mustCommand('git', ['add', '-A'], root);
  mustCommand('git', ['commit', '-q', '-m', 'fixture'], root);
}

function archive(ref, target) {
  fs.mkdirSync(target, { recursive: true });
  const tarFile = `${target}.tar`;
  mustCommand('git', ['archive', '--format=tar', '-o', tarFile, ref], repoRoot);
  mustCommand('tar', ['-xf', tarFile, '-C', target], repoRoot);
  fs.rmSync(tarFile, { force: true });
}

function plan(sourceRoot, workspace) {
  const result = command(process.execPath, [path.join(sourceRoot, 'bin', 'jumao.js'), 'plan', workspace, '--force'], sourceRoot);
  if (result.status !== 0) throw new Error(`${result.command}\n${result.stderr || result.stdout}`);
  const latest = readJSON(path.join(workspace, '.jumao', 'latest-run.json'));
  const runRoot = path.join(workspace, latest.runPath);
  return {
    latest,
    manifest: readJSON(path.join(runRoot, 'manifest.json')),
    taskPlan: readJSON(path.join(runRoot, 'task-plan.json')),
    planMarkdown: fs.readFileSync(path.join(workspace, 'tasks', 'jumao-agent-plan.md'), 'utf8')
  };
}

function executionFiles() {
  return new Set(['execution-context.json', 'execution-handoff.json', 'completion-receipt.json', 'codex-final.md', 'codex-stdout.log', 'codex-stderr.log']);
}

function changedPaths(workspace) {
  const status = command('git', ['status', '--porcelain=v1'], workspace).stdout;
  const ignored = executionFiles();
  const paths = status.split('\n').filter(Boolean).map((line) => line.slice(3).replace(/^"|"$/g, ''))
    .filter((relativePath) => !relativePath.startsWith('.jumao/') && !relativePath.startsWith('tasks/') && !ignored.has(relativePath));
  const expanded = [];
  const visit = (relativePath) => {
    const fullPath = path.join(workspace, relativePath);
    if (!fs.existsSync(fullPath)) return;
    if (!fs.statSync(fullPath).isDirectory()) {
      expanded.push(relativePath);
      return;
    }
    for (const entry of fs.readdirSync(fullPath)) visit(path.join(relativePath, entry));
  };
  for (const relativePath of paths) visit(relativePath);
  return [...new Set(expanded)];
}

function changedText(workspace, paths) {
  const chunks = [];
  const diff = paths.length > 0 ? command('git', ['diff', '--no-ext-diff', '--', ...paths], workspace).stdout : '';
  chunks.push(diff);
  for (const relativePath of paths) {
    const fullPath = path.join(workspace, relativePath);
    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()
      && command('git', ['ls-files', '--error-unmatch', '--', relativePath], workspace).status !== 0) {
      chunks.push(fs.readFileSync(fullPath, 'utf8'));
    }
  }
  return chunks.join('\n').toLowerCase();
}

function changedFileContents(workspace, paths) {
  return paths.flatMap((relativePath) => {
    const fullPath = path.join(workspace, relativePath);
    if (!fs.existsSync(fullPath) || !fs.statSync(fullPath).isFile()) return [];
    try { return [{ path: relativePath, content: fs.readFileSync(fullPath, 'utf8') }]; } catch { return []; }
  });
}

function goalCompletion(caseId, goals, implementationText, commandResults) {
  const text = implementationText;
  const passed = commandResults.some((result) => result.label === 'npm test' && result.status === 0);
  return goals.map((goal) => ({
    goalId: goal.goalId,
    completed: Boolean(goalPattern(goal.goalId)?.test(text) && (caseId !== 'existing-node-cli-refactor' || passed)),
    reason: goalPattern(goal.goalId)?.test(text) ? 'changed implementation/test evidence matched the explicit goal.' : 'no changed implementation evidence matched the explicit goal.'
  }));
}

function goalPattern(goalId) {
  return {
    'goal:web-entry': /<html|web.?entry|网页入口|login.*form|form.*login|sign.?in.*button/,
    'goal:anonymous-browsing': /anonymous|guest|匿名|访客|browse|catalog/,
    'goal:login-flow': /login|sign.?in|登录|登陆|account|账号/,
    'goal:membership-state': /membership|member|会员/,
    'goal:membership-entitlement': /entitlement|benefit|权益|会员权益/,
    'goal:health-authorization': /healthkit|requestauthorization|授权请求|健康数据授权/,
    'goal:health-refusal': /denied|refusal|授权拒绝|拒绝授权/,
    'goal:health-local-deletion': /delete.*(health|local)|删除.*(健康|本地)/,
    'goal:health-non-diagnostic': /non.?diagnostic|非诊断|不提供诊断|不预测疾病/,
    'goal:cli-json': /--json|json.stringify|json 输出/,
    'goal:cli-text-compatibility': /items: 0|text output|文本输出|renderreport/,
    'goal:signup-draft': /signup|sign.?up|报名|draft|草稿/,
    'goal:migration-backup': /backup|备份/,
    'goal:migration-script': /migration.*script|迁移脚本/,
    'goal:migration-rollback': /rollback|回滚/,
    'goal:migration-validation': /dry.?run|test data|测试数据|模拟数据|迁移.*测试/
  }[goalId] || null;
}

function constraintViolations(caseId, files, paths) {
  const violations = detectRealSideEffects(files).map((item) => `${item.kind}: ${item.path}`);
  if (caseId === 'existing-node-cli-refactor' && paths.some((item) => /html|css|tsx|jsx|vue|svelte/.test(item))) {
    violations.push('CLI execution changed a web UI file.');
  }
  return violations;
}

function invalidModifications(caseId, paths) {
  if (caseId === 'existing-node-cli-refactor') {
    return paths.filter((item) => !/^(bin|src|test)\//.test(item) && item !== 'package.json' && !item.startsWith('product/'));
  }
  return [];
}

function runProjectChecks(caseId, workspace) {
  const results = [];
  const packageFile = path.join(workspace, 'package.json');
  if (fs.existsSync(packageFile)) {
    const packageJSON = readJSON(packageFile);
    if (packageJSON.scripts?.test) {
      const result = command('npm', ['test'], workspace);
      results.push({ label: 'npm test', ...result });
    }
    if (packageJSON.scripts?.build) {
      const result = command('npm', ['run', 'build'], workspace);
      results.push({ label: 'npm run build', ...result });
    } else {
      results.push({ label: 'build', status: null, skipped: true, reason: 'NO_BUILD_SCRIPT' });
    }
  }
  if (caseId === 'existing-node-cli-refactor') {
    for (const args of [['node', 'bin/report.js'], ['node', 'bin/report.js', '--json']]) {
      const result = command(args[0], args.slice(1), workspace);
      results.push({ label: args.join(' '), ...result });
    }
  }
  const project = fs.readdirSync(workspace).find((item) => item.endsWith('.xcodeproj'));
  if (project) {
    const projectPath = path.join(workspace, project);
    const scheme = path.basename(project, '.xcodeproj');
    const destination = concreteSimulatorDestination();
    const destinationArgs = destination ? ['-destination', destination] : [];
    const build = command('xcodebuild', ['-project', projectPath, '-scheme', scheme, '-sdk', 'iphonesimulator', ...destinationArgs, 'CODE_SIGNING_ALLOWED=NO', 'build'], workspace, { timeout: 600000 });
    results.push({ label: 'xcodebuild build', ...build });
    const test = command('xcodebuild', ['-project', projectPath, '-scheme', scheme, '-sdk', 'iphonesimulator', ...destinationArgs, 'CODE_SIGNING_ALLOWED=NO', 'test'], workspace, { timeout: 600000 });
    results.push({ label: 'xcodebuild test', ...test });
  }
  return results;
}

function concreteSimulatorDestination() {
  const result = command('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], repoRoot);
  if (result.status !== 0) return null;
  try {
    const devices = Object.values(JSON.parse(result.stdout).devices || {}).flat();
    const device = devices.find((item) => item.isAvailable && /^iPhone/.test(item.name) && item.udid)
      || devices.find((item) => item.isAvailable && item.udid);
    return device ? `platform=iOS Simulator,id=${device.udid}` : null;
  } catch {
    return null;
  }
}

async function codexRun(sourceRoot, workspace, outputFile, handoff) {
  const contextFile = path.join(workspace, 'execution-context.json');
  writeJSON(contextFile, executionContext);
  writeJSON(path.join(workspace, 'execution-handoff.json'), handoff);
  const result = await runCompletionSession({
    binary: 'codex',
    args: [
    'exec', '--ephemeral', '--skip-git-repo-check', '-s', 'danger-full-access',
    '-m', 'gpt-5.6-terra', '-c', 'model_reasoning_effort="high"',
    '-c', 'service_tier="default"', '-C', workspace, '-o', outputFile, executionPrompt
    ],
    cwd: sourceRoot,
    receiptFile: path.join(workspace, handoff.completionReceipt.file),
    expectedGoals: handoff.goalCoverage.map((item) => item.goalId),
    timeout: lifecycleTimeouts,
    validateReceipt: (value, goals) => completionReceiptFor(value, goals, [])
  });
  writeText(path.join(workspace, 'codex-stdout.log'), result.stdout);
  writeText(path.join(workspace, 'codex-stderr.log'), result.stderr);
  return result;
}

function planTaskText(taskPlan) {
  return [
    ...(taskPlan.firstStage || []),
    ...(taskPlan.laterStages || []),
    ...(taskPlan.priorityTasks || []).map((task) => task.task)
  ].join('\n').toLowerCase();
}

function taskCoveredGoalCount(goals, planned) {
  const taskPlan = planned.taskPlan;
  if (planned.taskPlan.goalCoverage?.length > 0) {
    return goals.filter((goal) => taskPlan.goalCoverage.some((item) => item.goalId === goal.goalId && item.status === 'covered')).length;
  }
  const text = planTaskText(taskPlan);
  return goals.filter((goal) => goalPattern(goal.goalId)?.test(text)).length;
}

async function runOne({ sourceRoot, benchmarkCase, version, repetition, tempRoot, expectedGoals }) {
  const workspace = path.join(tempRoot, version, benchmarkCase.id, `run-${repetition}`);
  materialize(workspace, benchmarkCase);
  initializeFixture(workspace);
  const fixtureHash = fixtureFingerprint(benchmarkCase);
  const planned = plan(sourceRoot, workspace);
  const handoff = executionHandoffForPlan({
    goals: (planned.taskPlan.goalCoverage || []).map((goal) => ({ goalId: goal.goalId, label: goal.label })),
    priorityTasks: planned.taskPlan.priorityTasks || [],
    workspace,
    executionContext
  });
  const outputFile = path.join(workspace, 'codex-final.md');
  const codex = handoff.ready
    ? await codexRun(sourceRoot, workspace, outputFile, handoff)
    : { status: null, timedOut: false, stdout: '', stderr: 'Execution handoff is not actionable.', lifecycleResult: 'incomplete', receipt: null };
  const paths = changedPaths(workspace);
  const implementationText = changedText(workspace, paths);
  const files = changedFileContents(workspace, paths);
  const checks = runProjectChecks(benchmarkCase.id, workspace);
  const violations = constraintViolations(benchmarkCase.id, files, paths);
  const validatedReceipt = codex.receipt
    ? completionReceiptFor(codex.receipt.receipt, expectedGoals.map((goal) => goal.goalId), violations)
    : null;
  const goals = goalCompletion(benchmarkCase.id, expectedGoals, implementationText, checks);
  const blockedGoals = (planned.taskPlan.goalCoverage || []).filter((goal) => goal.status === 'blocked').map((goal) => goal.goalId);
  const completedGoalIds = goals.filter((goal) => goal.completed).map((goal) => goal.goalId);
  const omissions = goals.filter((goal) => !goal.completed && !blockedGoals.includes(goal.goalId)).map((goal) => goal.goalId);
  const finalText = fs.existsSync(outputFile) ? fs.readFileSync(outputFile, 'utf8').toLowerCase() : '';
  const stoppedForAuthorization = /需要.*确认|请.*批准|owner.*approval|human.*approval|等待.*确认|cannot proceed|不能继续/.test(finalText)
    && paths.length === 0;
  const commitsAfter = command('git', ['rev-list', '--count', 'HEAD'], workspace).stdout.trim();
  const result = {
    caseId: benchmarkCase.id,
    version,
    repetition,
    sourceRef: version === 'v0.3.1' ? baselineRef : repairRef,
    runtimeSourceHash: hashFile(path.join(sourceRoot, 'src', 'core', 'planning-runtime.js')),
    fixtureFingerprint: fixtureHash,
    executionContext,
    planner: {
      runId: planned.latest.runId,
      priorityTaskCount: planned.taskPlan.priorityTasks?.length || 0,
      goals: expectedGoals,
      handoffReady: planned.taskPlan.handoffReady,
      actionability: handoff,
      executionBoundaries: planned.taskPlan.executionBoundaries || []
    },
    codex: {
      status: codex.status,
      timedOut: codex.timedOut,
      lifecycleResult: codex.lifecycleResult,
      completionReceipt: validatedReceipt?.receipt || null,
      completionReceiptValid: Boolean(validatedReceipt?.valid),
      forcedCleanup: Boolean(codex.forcedCleanup),
      stoppedForAuthorization,
      commitsAfter,
      finalOutput: outputFile
    },
    metrics: {
      explicitGoalCount: goals.length,
      taskCoveredGoalCount: taskCoveredGoalCount(expectedGoals, planned),
      actuallyCompletedGoalCount: completedGoalIds.length,
      reasonablyBlockedGoalCount: blockedGoals.length,
      unjustifiedOmissionCount: omissions.length,
      completedGoalIds,
      blockedGoalIds: blockedGoals,
      omittedGoalIds: omissions,
      invalidModifications: invalidModifications(benchmarkCase.id, paths),
      constraintViolations: violations,
      tests: checks,
      humanInterventionCount: stoppedForAuthorization ? 1 : 0,
      reworkCount: (finalText.match(/rework|返工|retry|again|重新/g) || []).length,
      externalSideEffects: false,
      modifiedFiles: paths,
      planMarkdownIncludesGoals: (planned.taskPlan.goalCoverage || []).every((goal) => planned.planMarkdown.includes(goal.goalId))
    }
  };
  return result;
}

function hashFile(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function runFrozenAdversarialChecks(sourceRoot, tempRoot) {
  const checks = [];
  for (const benchmarkCase of adversarialCases) {
    const workspace = path.join(tempRoot, 'adversarial', benchmarkCase.id);
    materialize(workspace, benchmarkCase);
    const planned = plan(sourceRoot, workspace);
    const tasks = planned.taskPlan.priorityTasks || [];
    let passed = true;
    if (benchmarkCase.id === 'assessed-no-change') passed = tasks.length === 0;
    if (benchmarkCase.id === 'triggered-insufficient-evidence') passed = tasks.length === 0 && planned.manifest.blockingQuestions.length > 0;
    if (benchmarkCase.id === 'applicable-no-risk') passed = tasks.length === 0;
    if (benchmarkCase.id === 'bilingual-negation-ambiguity') passed = planned.manifest.blockingQuestions.length > 0 && tasks.length === 0;
    if (benchmarkCase.id === 'conflicting-evidence') passed = planned.manifest.blockingQuestions.length > 0 && tasks.length === 0;
    if (benchmarkCase.id === 'overlapping-role-tasks') passed = tasks.some((task) => task.contributingRoles.length > 1 && task.contributionImpacts.some((impact) => impact.impactType === 'merged_task'));
    if (benchmarkCase.id === 'monorepo-scoped-constraint') passed = tasks.length > 0 && tasks.every((task) => task.scope?.paths?.includes('packages/admin/**'));
    if (benchmarkCase.id === 'irreversible-auth-migration') {
      const text = tasks.map((task) => task.task).join('\n');
      passed = /备份/.test(text) && /回滚/.test(text) && /验证|测试/.test(text)
        && planned.taskPlan.executionBoundaries.some((item) => item.phase === 'execute' && item.status === 'blocked');
    }
    checks.push({ id: benchmarkCase.id, expected: benchmarkCase.expected, passed, priorityTaskCount: tasks.length, blocked: planned.manifest.blockingQuestions.length });
  }
  return checks;
}

function runOriginalCaseChecks(sourceRoot, tempRoot) {
  return benchmarkCases.map((benchmarkCase) => {
    const workspace = path.join(tempRoot, 'original-cases', benchmarkCase.id);
    materialize(workspace, benchmarkCase);
    const planned = plan(sourceRoot, workspace);
    const tasks = planned.taskPlan.priorityTasks || [];
    const text = tasks.map((task) => task.task).join('\n');
    let passed = true;
    if (benchmarkCase.id === 'saas-web-membership') {
      const webTask = tasks.find((task) => task.goalIds?.includes('goal:web-entry'));
      passed = Boolean(webTask && /完成条件/.test(webTask.task) && /入口/.test(webTask.task) && planned.taskPlan.handoffReady);
    }
    if (benchmarkCase.id === 'explicit-negative-constraints') {
      passed = /活动报名草稿/.test(text) && !/会员|订阅/.test(text);
    }
    if (benchmarkCase.id === 'high-risk-health-data') {
      passed = /HealthKit/.test(text) && /授权拒绝/.test(text) && /删除本地健康趋势数据/.test(text)
        && /非诊断/.test(text) && /xcodebuild test/.test(text);
    }
    if (benchmarkCase.id === 'existing-node-cli-refactor') {
      passed = /--json/.test(text) && /文本输出/.test(text) && !/网页入口|页面 UI|Xcode/.test(text);
    }
    return { id: benchmarkCase.id, title: benchmarkCase.title, passed, priorityTaskCount: tasks.length, handoffReady: planned.taskPlan.handoffReady };
  });
}

async function main() {
  const selected = benchmarkCases.filter((benchmarkCase) => targetIds.includes(benchmarkCase.id));
  if (selected.length !== targetIds.length) throw new Error('Execution target case missing.');
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-execution-handoff-'));
  const repairRoot = path.join(tempRoot, 'sources', 'repair');
  fs.rmSync(resultsRoot, { recursive: true, force: true });
  fs.mkdirSync(resultsRoot, { recursive: true });
  try {
    archive(repairRef, repairRoot);
    const adversarial = runFrozenAdversarialChecks(repairRoot, tempRoot);
    writeJSON(path.join(resultsRoot, 'adversarial.json'), adversarial);
    const originalCases = runOriginalCaseChecks(repairRoot, tempRoot);
    writeJSON(path.join(resultsRoot, 'original-cases.json'), originalCases);
    const expectedGoals = new Map();
    for (const benchmarkCase of selected) {
      const goalWorkspace = path.join(tempRoot, 'goal-catalog', benchmarkCase.id);
      materialize(goalWorkspace, benchmarkCase);
      const goalPlan = plan(repairRoot, goalWorkspace);
      expectedGoals.set(benchmarkCase.id, (goalPlan.taskPlan.goalCoverage || []).map((goal) => ({
        goalId: goal.goalId,
        label: goal.label
      })));
    }
    const runs = [];
    for (const benchmarkCase of selected) {
      for (let repetition = 1; repetition <= repetitions; repetition += 1) {
        process.stdout.write(`Running ${benchmarkCase.id} repair ${repetition}/${repetitions}\n`);
        const result = await runOne({ sourceRoot: repairRoot, benchmarkCase, version: 'repair', repetition, tempRoot, expectedGoals: expectedGoals.get(benchmarkCase.id) });
        runs.push(result);
        writeJSON(path.join(resultsRoot, 'runs', benchmarkCase.id, `repair-${repetition}.json`), result);
      }
    }
    writeJSON(path.join(resultsRoot, 'summary.json'), {
      generatedAt: new Date().toISOString(),
      baselineRef,
      repairRef,
      frozenBaselineResolvedRef: mustCommand('git', ['rev-parse', baselineRef], repoRoot).stdout.trim(),
      repairResolvedRef: mustCommand('git', ['rev-parse', repairRef], repoRoot).stdout.trim(),
      repetitions,
      executionPrompt,
      executionContext,
      adversarial,
      originalCases,
      runs
    });
    writeText(path.join(resultsRoot, 'README.md'), [
      '# Execution Handoff Validation', '',
      `- frozen baseline (not re-run): ${baselineRef}`,
      `- repair: ${repairRef}`,
      `- repetitions: ${repetitions}`,
      `- runs: ${runs.length}`,
      '',
      '每次执行都使用独立临时 worktree、相同 Codex CLI/model/config/prompt 和 session-only sandbox execution context。结果 JSON 位于 `runs/`。', ''
    ].join('\n'));
    process.stdout.write(`Wrote ${path.relative(repoRoot, resultsRoot)}\n`);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

main().catch((error) => { process.stderr.write(`${error.stack || error.message}\n`); process.exitCode = 1; });
