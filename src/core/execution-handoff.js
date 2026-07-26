export function sandboxExecutionContext(authorizedScope = ['current temporary worktree']) {
  const scope = Array.isArray(authorizedScope) ? authorizedScope : [authorizedScope];
  return {
    executionMode: 'sandbox_implementation',
    authorizedScope: scope.map((item) => String(item)).filter(Boolean),
    allowPrepare: true,
    allowValidate: true,
    allowProductionEffects: false
  };
}

export function renderExecutionContext(context) {
  return JSON.stringify(context, null, 2);
}

export function buildExecutionHandoff({ goals = [], tasks = [], executionContext = {} } = {}) {
  const normalizedTasks = Array.isArray(tasks) ? tasks.map((task) => ({
    taskId: task.taskId || task.id || null,
    goalIds: Array.isArray(task.goalIds) ? task.goalIds : [],
    action: text(task.action),
    target: text(task.target),
    doneWhen: text(task.doneWhen),
    phase: task.phase || 'prepare',
    surface: task.surface || null,
    blocked: Boolean(task.blocked)
  })) : [];
  const goalCoverage = (Array.isArray(goals) ? goals : []).map((goal) => {
    const candidates = normalizedTasks.filter((task) => task.goalIds.includes(goal.goalId));
    if (candidates.length === 0) return uncovered(goal, 'missing_task');
    const valid = candidates.find((task) => taskIsActionableForGoal(task, goal.goalId, executionContext));
    if (valid) return { goalId: goal.goalId, label: goal.label, status: 'covered', reason: null, taskId: valid.taskId };
    return uncovered(goal, actionabilityFailure(candidates[0], goal.goalId, executionContext));
  });
  return {
    ready: goalCoverage.every((goal) => goal.status === 'covered'),
    goalCoverage,
    tasks: normalizedTasks
  };
}

function taskIsActionableForGoal(task, goalId, context) {
  return !task.blocked
    && phaseAllowed(task.phase, context)
    && Boolean(task.action)
    && Boolean(task.target)
    && Boolean(task.doneWhen)
    && !(goalId === 'goal:web-entry' && task.surface === 'data');
}

function actionabilityFailure(task, goalId, context) {
  if (task.blocked || !phaseAllowed(task.phase, context)) return 'blocked_goal';
  if (!task.action) return 'missing_action';
  if (!task.target) return 'missing_target';
  if (!task.doneWhen) return 'missing_acceptance_check';
  if (goalId === 'goal:web-entry' && task.surface === 'data') return 'missing_task';
  return 'missing_task';
}

export function validationBootstrapFor({ platforms = [], files = [], goalIds = [], executionContext = {} } = {}) {
  if (!executionContext.allowPrepare || !executionContext.allowValidate) return null;
  if (platforms.includes('Node CLI') || !platforms.includes('iOS')) return null;
  if (!goalIds.some((goalId) => goalId.startsWith('goal:health-'))) return null;
  if (hasRunnableXcodeTestAction(files)) return null;
  const project = (Array.isArray(files) ? files : []).find((file) => /\.xcodeproj\//.test(file.path || ''))?.path || null;
  return {
    phase: 'prepare',
    goalIds: goalIds.filter((goalId) => goalId.startsWith('goal:health-')),
    action: project
      ? '检查现有 Xcode project、scheme 和 test action；若缺失，为本次健康目标创建或关联最小单元测试 target。'
      : '创建 iPhone 最小工程时同时创建本次健康目标的最小单元测试 target 和可运行 test action。',
    target: project || '新建 iPhone 工程的共享 scheme 与 HealthTrendTests target',
    doneWhen: 'HealthKit 授权拒绝状态、本地删除和非诊断状态可由本地 mock 验证，且 xcodebuild test 返回 0。',
    surface: 'test'
  };
}

export function executionHandoffForPlan({ goals = [], priorityTasks = [], workspace = '', executionContext = {}, defaultDoneWhen = null } = {}) {
  const tasks = (Array.isArray(priorityTasks) ? priorityTasks : []).map((task) => actionableTaskFor(task, workspace, defaultDoneWhen));
  return buildExecutionHandoff({ goals, tasks, executionContext });
}

function actionableTaskFor(task, workspace, defaultDoneWhen = null) {
  const goalIds = Array.isArray(task.goalIds) ? task.goalIds : [];
  const source = String(task.task || '');
  if (goalIds.includes('goal:web-entry')) {
    const entry = existingWebEntry(workspace);
    return {
      taskId: task.taskId,
      goalIds,
      phase: 'prepare',
      surface: 'web',
      action: entry
        ? '在现有网页入口连接匿名、本地假登录和本地假会员状态及权益行为。'
        : '使用现有技术栈创建最小本地网页入口；没有框架时创建静态本地页面，并连接匿名、本地假登录和本地假会员状态及权益行为。',
      target: entry || 'index.html',
      doneWhen: '本地入口可定位，显示匿名状态，可切换本地假登录和会员状态，并显示至少一个会员权益行为。'
    };
  }
  if (goalIds.some((goalId) => goalId.startsWith('goal:health-'))) {
    const requiresXcodeTest = /xcodebuild test/i.test(source);
    return {
      taskId: task.taskId,
      goalIds,
      phase: /测试|验证|xcodebuild/i.test(source) ? 'validate' : 'prepare',
      surface: 'health',
      action: source,
      target: 'HealthTrend 授权状态、局部数据存储和 HealthTrendTests',
      doneWhen: requiresXcodeTest
        ? '授权拒绝状态、本地删除和非诊断状态可由本地 mock 验证，xcodebuild test 返回 0，且不读取或上传真实健康数据。'
        : '授权拒绝状态、本地删除和非诊断状态可由本地 mock 验证，且不读取或上传真实健康数据。'
    };
  }
  if (goalIds.some((goalId) => goalId.startsWith('goal:cli-'))) {
    return {
      taskId: task.taskId,
      goalIds,
      phase: /验证|测试/.test(source) ? 'validate' : 'prepare',
      surface: 'cli',
      action: source,
      target: existingPath(workspace, ['bin/report.js', 'src/report.js', 'test/report.test.js']) || '现有 report CLI 与回归测试',
      doneWhen: 'node bin/report.js 保持文本输出，node bin/report.js --json 输出可解析 JSON，且 npm test 通过。'
    };
  }
  const embeddedDoneWhen = source.match(/完成条件[：:]\s*([^\n]+)/);
  const embeddedFile = source.match(/[\w@./-]+\.(?:js|mjs|ts|tsx|jsx|swift|html|css|json|md|py|vue|svelte)\b/);
  return {
    taskId: task.taskId,
    goalIds,
    phase: /验证|测试|verify|test/i.test(source) ? 'validate' : 'prepare',
    action: source || null,
    target: task.scope?.paths?.join(', ') || embeddedFile?.[0] || null,
    doneWhen: embeddedDoneWhen?.[1]?.trim() || defaultDoneWhen || null,
    surface: null
  };
}

function existingWebEntry(workspace) {
  if (!workspace || !isDirectory(workspace)) return null;
  const candidates = ['index.html', 'src/App.jsx', 'src/App.tsx', 'src/routes/catalog.js', 'src/routes/index.js'];
  return existingPath(workspace, candidates);
}

function existingPath(workspace, candidates) {
  return candidates.find((candidate) => fsExists(workspace, candidate)) || null;
}

function hasRunnableXcodeTestAction(files) {
  return (Array.isArray(files) ? files : []).some((file) => /\.xcscheme$/.test(file.path || '')
    && /<TestAction[\s>]/.test(file.searchText || '')
    && /TestableReference/.test(file.searchText || ''));
}

function phaseAllowed(phase, context) {
  return phase === 'validate' ? Boolean(context.allowValidate) : Boolean(context.allowPrepare);
}

function uncovered(goal, reason) {
  return { goalId: goal.goalId, label: goal.label, status: 'blocked', reason, taskId: null };
}

function text(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function isDirectory(value) {
  try { return fs.statSync(value).isDirectory(); } catch { return false; }
}

function fsExists(workspace, relativePath) {
  return fs.existsSync(`${workspace}${relativePath ? `/${relativePath}` : ''}`);
}
import fs from 'node:fs';
