import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { completionReceiptFile, crossValidateReceipt, parseCompletionReceiptFile } from './completion-receipt.js';
import { detectRealSideEffects } from './execution-validation.js';

// 与冻结验证使用同一套目标证据标准；没有列出的 goalId 属于「橘猫无法独立核对」，
// 只会记为核验受限，不会当成谎报。
const goalEvidencePatterns = {
  'goal:web-entry': /<html|web.?entry|网页入口|login.*form|form.*login|sign.?in.*button/,
  'goal:anonymous-browsing': /anonymous|guest|匿名|访客|browse|catalog/,
  'goal:login-flow': /login|sign.?in|登录|登陆|account|账号/,
  'goal:membership-state': /membership|member|会员/,
  'goal:membership-entitlement': /entitlement|benefit|权益|会员权益/,
  'goal:health-authorization': /healthkit|requestauthorization|授权请求|健康数据授权/,
  'goal:health-refusal': /denied|refusal|授权拒绝|拒绝授权/,
  'goal:health-local-deletion': /delete.*(health|local)|删除.*(健康|本地)/,
  'goal:health-non-diagnostic': /non.?diagnostic|非诊断|不提供诊断|不预测疾病/,
  'goal:cli-json': /--json|json\.stringify|json 输出/,
  'goal:cli-text-compatibility': /items: 0|text output|文本输出|renderreport/,
  'goal:signup-draft': /signup|sign.?up|报名|draft|草稿/,
  'goal:migration-backup': /backup|备份/,
  'goal:migration-script': /migration.*script|迁移脚本/,
  'goal:migration-rollback': /rollback|回滚/,
  'goal:migration-validation': /dry.?run|test data|测试数据|模拟数据|迁移.*测试/
};

const internalPathPrefixes = ['.jumao/', 'tasks/', 'governance/'];

function command(binary, args, cwd, timeout = 240000) {
  const result = spawnSync(binary, args, {
    cwd,
    encoding: 'utf8',
    timeout,
    maxBuffer: 16 * 1024 * 1024
  });
  return {
    status: result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    failedToRun: Boolean(result.error)
  };
}

function isGitWorkspace(workspacePath) {
  const probe = command('git', ['rev-parse', '--is-inside-work-tree'], workspacePath, 10000);
  return probe.status === 0 && probe.stdout.trim() === 'true';
}

function changedPaths(workspacePath) {
  const status = command('git', ['status', '--porcelain=v1'], workspacePath, 30000);
  if (status.status !== 0) return [];
  const paths = status.stdout.split('\n').filter(Boolean)
    .map((line) => line.slice(3).replace(/^"|"$/g, ''))
    .filter((relativePath) => !internalPathPrefixes.some((prefix) => relativePath.startsWith(prefix)));
  const expanded = [];
  const visit = (relativePath) => {
    const fullPath = path.join(workspacePath, relativePath);
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

function changedText(workspacePath, paths) {
  const chunks = [];
  if (paths.length > 0) {
    chunks.push(command('git', ['diff', '--no-ext-diff', '--', ...paths], workspacePath, 60000).stdout);
    chunks.push(command('git', ['diff', '--no-ext-diff', '--cached', '--', ...paths], workspacePath, 60000).stdout);
  }
  for (const relativePath of paths) {
    const fullPath = path.join(workspacePath, relativePath);
    if (!fs.existsSync(fullPath) || !fs.statSync(fullPath).isFile()) continue;
    const tracked = command('git', ['ls-files', '--error-unmatch', '--', relativePath], workspacePath, 10000);
    if (tracked.status !== 0) {
      try { chunks.push(fs.readFileSync(fullPath, 'utf8')); } catch { /* unreadable file adds no evidence */ }
    }
  }
  return chunks.join('\n').toLowerCase();
}

function changedFileContents(workspacePath, paths) {
  return paths.flatMap((relativePath) => {
    const fullPath = path.join(workspacePath, relativePath);
    if (!fs.existsSync(fullPath) || !fs.statSync(fullPath).isFile()) return [];
    try { return [{ path: relativePath, content: fs.readFileSync(fullPath, 'utf8') }]; } catch { return []; }
  });
}

function runProjectChecks(workspacePath) {
  const checks = [];
  const packageFile = path.join(workspacePath, 'package.json');
  if (fs.existsSync(packageFile)) {
    let packageJSON = null;
    try { packageJSON = JSON.parse(fs.readFileSync(packageFile, 'utf8')); } catch { packageJSON = null; }
    if (packageJSON?.scripts?.test) {
      checks.push({ label: 'npm test', ...command('npm', ['test'], workspacePath, 300000) });
    }
  }
  const project = fs.readdirSync(workspacePath).find((item) => item.endsWith('.xcodeproj'));
  if (project) {
    const scheme = path.basename(project, '.xcodeproj');
    checks.push({
      label: 'xcodebuild test',
      ...command('xcodebuild', [
        '-project', path.join(workspacePath, project), '-scheme', scheme,
        '-sdk', 'iphonesimulator', 'CODE_SIGNING_ALLOWED=NO', 'test'
      ], workspacePath, 600000)
    });
  }
  return checks.filter((check) => !check.failedToRun);
}

function latestGoalCoverage(workspacePath) {
  try {
    const latest = JSON.parse(fs.readFileSync(path.join(workspacePath, '.jumao', 'latest-run.json'), 'utf8'));
    const taskPlan = JSON.parse(fs.readFileSync(path.join(workspacePath, latest.runPath, 'task-plan.json'), 'utf8'));
    return Array.isArray(taskPlan.goalCoverage) ? taskPlan.goalCoverage : [];
  } catch {
    return null;
  }
}

export function verifyWorkspaceReceipt(workspacePath, options = {}) {
  const runChecks = options.runChecks !== false;
  const root = path.resolve(workspacePath);
  const receiptPath = path.join(root, completionReceiptFile);
  if (!fs.existsSync(receiptPath)) {
    return {
      ok: false,
      state: 'no_receipt',
      runChecks,
      message: '这个项目里还没有 AI 交回的完成回执。先让 AI 干完活，它会把回执写到项目里。'
    };
  }

  const parsed = parseCompletionReceiptFile(fs.readFileSync(receiptPath, 'utf8'));
  if (!parsed.receipt) {
    return {
      ok: true,
      state: 'illegal',
      runChecks,
      issues: parsed.issues,
      error: parsed.error,
      message: 'AI 交了回执，但内容不完整或格式不对。让它重新交一份完整回执。'
    };
  }
  const receipt = parsed.receipt;

  const limits = [];
  const coverage = latestGoalCoverage(root);
  const knownGoalIds = coverage === null ? null : coverage.map((goal) => goal.goalId);
  if (coverage === null) limits.push('没有找到最近一次规划记录，无法核对目标清单。');

  const gitAvailable = isGitWorkspace(root);
  let paths = [];
  let text = '';
  let files = [];
  if (gitAvailable) {
    paths = changedPaths(root);
    text = changedText(root, paths);
    files = changedFileContents(root, paths);
    if (paths.length === 0) {
      limits.push('当前没有未提交的改动，目标证据和副作用只能核对已提交内容之外的部分。');
    }
  } else {
    limits.push('项目没有使用 git，橘猫无法独立核对文件改动证据。');
  }

  const measurableGoalIds = (knownGoalIds || [])
    .filter((goalId) => goalEvidencePatterns[goalId] && gitAvailable && paths.length > 0);
  const unmeasurable = (knownGoalIds || []).filter((goalId) => !measurableGoalIds.includes(goalId));
  if (knownGoalIds && unmeasurable.length > 0 && gitAvailable && paths.length > 0) {
    limits.push(`有 ${unmeasurable.length} 个目标橘猫没有独立证据标准，只能以回执自述为准。`);
  }
  const measuredCompletedGoalIds = measurableGoalIds
    .filter((goalId) => goalEvidencePatterns[goalId].test(text));

  const measuredChecks = runChecks ? runProjectChecks(root) : [];
  if (!runChecks) {
    limits.push('已跳过项目测试（不会执行 npm test / xcodebuild test），验证声明只能以回执自述为准。只在你信任的项目上做完整核验。');
  } else if (measuredChecks.length === 0) {
    limits.push('项目里没有可重跑的标准测试，验证声明只能以回执自述为准。');
  }

  const sideEffects = files.length > 0 ? detectRealSideEffects(files) : [];

  const accounted = new Set([
    ...receipt.goalsCompleted,
    ...receipt.goalsBlocked.map((entry) => entry.goalId)
  ]);
  const unjustifiedOmissionGoalIds = (knownGoalIds || []).filter((goalId) => !accounted.has(goalId));

  const verdict = crossValidateReceipt({
    receipt,
    knownGoalIds: knownGoalIds || [...receipt.goalsCompleted, ...receipt.goalsBlocked.map((entry) => entry.goalId)],
    measuredCompletedGoalIds,
    measuredChecks,
    sideEffects,
    unjustifiedOmissionGoalIds,
    measurableGoalIds
  });

  const state = verdict.truthful ? (limits.length > 0 ? 'trusted_with_limits' : 'trusted') : 'untrusted';
  return {
    ok: true,
    state,
    runChecks,
    receipt,
    violations: verdict.violations,
    limits,
    measuredChecks: measuredChecks.map((check) => ({ label: check.label, status: check.status })),
    changedFiles: paths,
    message: verdictMessage(state, verdict.violations, limits)
  };
}

function verdictMessage(state, violations, limits) {
  if (state === 'trusted') {
    return '橘猫独立核验过了：回执和实际情况对得上。可以放心看结果。';
  }
  if (state === 'trusted_with_limits') {
    return `橘猫核验过能核对的部分，没有发现问题；但有 ${limits.length} 项橘猫没法独立核对，见下方说明。`;
  }
  return `回执和实际情况对不上（${violations.length} 处）。先看下面的问题，再决定要不要让 AI 返工。`;
}

export function renderVerifyReport(result) {
  const lines = ['# 橘猫回执核验', ''];
  lines.push(result.message, '');
  if (result.state === 'no_receipt' || result.state === 'illegal') {
    if (result.error) lines.push(`- 具体原因：${result.error}`);
    return lines.join('\n') + '\n';
  }
  if (result.violations?.length > 0) {
    lines.push('## 对不上的地方', '');
    for (const violation of result.violations) {
      lines.push(`- ${violationInPlainWords(violation)}`);
    }
    lines.push('');
  }
  if (result.limits?.length > 0) {
    lines.push('## 橘猫没法独立核对的部分', '');
    for (const limit of result.limits) lines.push(`- ${limit}`);
    lines.push('');
  }
  if (result.measuredChecks?.length > 0) {
    lines.push('## 橘猫自己重跑的检查', '');
    for (const check of result.measuredChecks) {
      lines.push(`- ${check.label}：${check.status === 0 ? '通过' : `没通过（退出码 ${check.status}）`}`);
    }
    lines.push('');
  }
  return lines.join('\n').trimEnd() + '\n';
}

function violationInPlainWords(violation) {
  const map = {
    unknown_goal: '回执里出现了计划里没有的目标',
    false_goal_claim: '回执说某个目标做完了，但改动里找不到对应证据',
    false_validation_claim: '回执说测试通过了，但橘猫自己重跑没通过',
    false_side_effect_claim: '回执说没有碰真实世界，但扫描发现了真实副作用',
    false_remaining_claim: '回执说没有剩余工作，但有目标被悄悄漏掉了'
  };
  return `${map[violation.rule] || violation.rule}（${violation.detail}）`;
}
