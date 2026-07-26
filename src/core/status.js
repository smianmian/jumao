import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { agentGroups } from './agent-registry.js';
import { completionReceiptFile, extractCompletionReceipt } from './completion-receipt.js';

const schemaVersion = '0.2.3';
const jumaoVersion = (() => {
  try {
    return JSON.parse(fs.readFileSync(new URL('../../package.json', import.meta.url), 'utf8')).version;
  } catch {
    return '0.0.0';
  }
})();

const artifactPaths = {
  agentReport: 'governance/agent-review-report.md',
  agentFindings: 'governance/agent-findings.json',
  codexGates: 'governance/codex-agent-gates.md',
  latestTaskPack: null
};

const catStates = {
  sleeping: {
    label: '还没检查',
    face: '( -.-)z',
    message: '还没检查。不是项目没问题，也不是项目失败。'
  },
  checking: {
    label: '正在检查',
    face: '( o.o)?',
    message: '正在检查。不是卡死。'
  },
  ready: {
    label: '可以继续',
    face: '( ^.^)',
    message: '可以继续做一个小任务。不是可以上线。'
  },
  blocked: {
    label: '需要处理',
    face: '( x.x)!',
    message: '有件要紧的事必须先处理，橘猫帮你停下来了。不是项目失败。'
  },
  packed: {
    label: '任务包已生成',
    face: '( ^o^)>',
    message: '任务包已生成。不是已复制剪贴板，也不是已发布。'
  }
};

const baseAgentIds = new Set([
  'founder_decision',
  'product_manager',
  'project_tech_lead',
  'ui_ux',
  'documentation_delivery'
]);

const groupMessages = {
  direction_entity: '先补主体、品牌和材料边界',
  product_design: '先补产品范围、页面状态和文案边界',
  tech_development: '先补账号、服务端、密钥或构建边界',
  data_privacy: '先补数据保存、删除和第三方工具边界',
  compliance_health: '先补合规、健康声明或证据边界',
  platform_qualification: '先补发布、审核或平台材料',
  revenue_operations: '先补收费、退款和对账规则',
  release_incident: '先补测试、发布清单和回滚计划'
};

export function isJumaoWorkspace(targetDir) {
  if (!fs.existsSync(targetDir)) return false;
  if (!fs.statSync(targetDir).isDirectory()) return false;

  return fs.existsSync(path.join(targetDir, 'product')) &&
    (fs.existsSync(path.join(targetDir, 'AGENTS.md')) || fs.existsSync(path.join(targetDir, 'CLAUDE.md')));
}

export function statusPath(targetDir) {
  return path.join(targetDir, '.jumao', 'status.json');
}

export function completionReceiptStage(targetDir) {
  const file = path.join(targetDir, completionReceiptFile);
  if (!fs.existsSync(file)) return null;
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch {
    return null;
  }
  let extraction = extractCompletionReceipt(raw);
  if (!extraction.receipt) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !parsed.jumaoCompletion && 'status' in parsed && 'goalsCompleted' in parsed) {
        extraction = extractCompletionReceipt(JSON.stringify({ jumaoCompletion: parsed }));
      }
    } catch {
      // 保持原始提取结果。
    }
  }
  if (!extraction.receipt) {
    return {
      stage: 'receipt_invalid',
      message: 'AI 交了一份回执，但内容不完整或格式不对。不是项目失败。',
      nextSafeTask: '让 AI 重新交一份完整回执，或重新跑一次这项工作。',
      receipt: null
    };
  }
  if (extraction.receipt.status === 'blocked' || extraction.receipt.goalsBlocked.length > 0) {
    return {
      stage: 'receipt_blocked',
      message: 'AI 交回执说有些目标没做完，原因写在回执里。不是失败。',
      nextSafeTask: '看看回执里被卡住的原因，补上信息后再让 AI 继续。',
      receipt: extraction.receipt
    };
  }
  return {
    stage: 'receipt_completed',
    message: 'AI 交回执说这次的活做完了。不是橘猫核验过的结论。',
    nextSafeTask: '对照回执里列的目标，自己点一点功能，确认真的做完了。',
    receipt: extraction.receipt
  };
}

function withCompletionReceipt(targetDir, status) {
  const receiptStage = completionReceiptStage(targetDir);
  if (receiptStage) status.completionReceipt = receiptStage;
  return status;
}

export function readJumaoStatus(targetDir) {
  const file = statusPath(targetDir);
  if (!fs.existsSync(file)) return withCompletionReceipt(targetDir, sleepingStatus(targetDir));

  try {
    return withCompletionReceipt(targetDir, JSON.parse(fs.readFileSync(file, 'utf8')));
  } catch {
    return makeStatus(targetDir, 'blocked', {
      blockers: [{
        title: '状态文件',
        message: '橘猫的状态记录坏了。重新做一次检查就能恢复，不影响你的项目内容。',
        source: '.jumao/status.json'
      }],
      nextSafeTask: '在橘猫里重新做一次检查，状态会自动恢复。',
      lastRun: { command: 'status', target: null, ok: false }
    });
  }
}

export function writeCheckingStatus(targetDir, run) {
  const previous = readExistingStatus(targetDir);

  return writeStatus(targetDir, makeStatus(targetDir, 'checking', {
    agentBoard: previous?.agentBoard || emptyAgentBoard(),
    blockers: Array.isArray(previous?.blockers) ? previous.blockers : [],
    artifacts: previous?.artifacts || {},
    lastRun: {
      command: run.command,
      target: run.target ?? null,
      ok: null
    }
  }));
}

export function writeDoctorStatus(targetDir, diagnosis) {
  const blockers = doctorBlockers(diagnosis);
  const state = blockers.length > 0 ? 'blocked' : 'ready';

  return writeStatus(targetDir, makeStatus(targetDir, state, {
    agentBoard: createAgentBoard(diagnosis.triggeredAgents, blockers),
    blockers,
    nextSafeTask: nextDoctorTask(blockers),
    lastRun: { command: 'doctor', target: null, ok: true }
  }));
}

export function writeCommandBlockedStatus(targetDir, run, message) {
  return writeStatus(targetDir, makeStatus(targetDir, 'blocked', {
    agentBoard: previousAgentBoard(targetDir, 1),
    blockers: [{
      title: '命令参数',
      message,
      source: run.command
    }],
    nextSafeTask: '先把上面提示的问题处理掉，再重新试一次。',
    lastRun: {
      command: run.command,
      target: run.target ?? null,
      ok: false
    }
  }));
}

export function writePackBlockedStatus(targetDir, target, strictResult) {
  return writeStatus(targetDir, makeStatus(targetDir, 'blocked', {
    agentBoard: previousAgentBoard(targetDir, Math.max(1, strictResult.errors.length)),
    blockers: strictResult.errors.slice(0, 3).map(strictBlocker),
    nextSafeTask: nextStrictTask(strictResult),
    lastRun: { command: 'pack', target, ok: false }
  }));
}

export function writePackedStatus(targetDir, target, outputPath) {
  const previous = readExistingStatus(targetDir);
  const latestTaskPack = path.relative(targetDir, outputPath);
  const blockers = Array.isArray(previous?.blockers) ? previous.blockers : [];

  return writeStatus(targetDir, makeStatus(targetDir, 'packed', {
    agentBoard: previous?.agentBoard || emptyAgentBoard(),
    blockers,
    cat: blockers.length > 0
      ? { message: '任务包已生成，但仍需先处理关键门禁。' }
      : {},
    nextSafeTask: '把任务包交给 AI 前，先让它总结目标、边界、风险和下一步。',
    artifacts: {
      latestTaskPack
    },
    lastRun: { command: 'pack', target, ok: true }
  }));
}

export function writePlanningStatus(targetDir, state, run) {
  if (!['checking', 'ready', 'blocked'].includes(state)) {
    throw new Error(`Unsupported planning status: ${state}`);
  }

  const blockers = state === 'blocked'
    ? planningBlockers(run)
    : [];
  const nextSafeTask = state === 'checking'
    ? '橘猫还在检查，请稍等。现在看到的还不是最终结果。'
    : state === 'ready'
      ? '计划已经写好。先让 AI 读一遍计划、用自己的话总结给你听，再开始动手。它可以写代码、做本地测试；但凡碰真实用户、真实数据或要花钱的事，它必须先回来问你。'
      : blockers[0]?.message || '先解决上面列出的问题，再重新做一次规划。';

  return writeStatus(targetDir, makeStatus(targetDir, state, {
    agentBoard: planningAgentBoard(run.groups || []),
    blockers,
    nextSafeTask,
    artifacts: {
      agentReport: run.runPath ? `${run.runPath}/planning-summary.md` : null,
      agentFindings: run.runPath ? `${run.runPath}/manifest.json` : '.jumao/status.json',
      codexGates: null,
      latestTaskPack: 'tasks/jumao-agent-plan.md'
    },
    lastRun: { command: 'plan', target: null, ok: state === 'checking' ? null : state === 'ready' },
    planningRun: run
  }));
}

export function renderStatus(status) {
  const state = status?.cat?.state || 'sleeping';
  const cat = catStates[state] || catStates.sleeping;
  const hasPackedBlockers = state === 'packed' && Array.isArray(status.blockers) && status.blockers.length > 0;
  const blockerLimit = hasPackedBlockers ? 2 : 3;
  const blockers = Array.isArray(status.blockers) ? status.blockers.slice(0, blockerLimit) : [];
  const lines = [
    ' /\\_/\\',
    cat.face,
    ' > ^ <',
    `橘猫状态：${status.cat?.label || cat.label}（${state}）`,
    `项目：${status.workspace?.name || '未知项目'}`,
    agentBoardLine(status.agentBoard)
  ];

  if (hasPackedBlockers) {
    lines.push('任务包已生成，但门禁仍需处理。');
  }

  if (blockers.length > 0) {
    lines.push('关键阻塞：');
    for (const blocker of blockers) {
      lines.push(`- ${blocker.title}：${blocker.message}`);
    }
  }

  if (status.completionReceipt) {
    lines.push(`回执：${status.completionReceipt.message}`);
  }

  lines.push(`下一步：${status.completionReceipt?.nextSafeTask || status.nextSafeTask || cat.message}`);
  lines.push(`详情：${status.artifacts?.agentFindings || '.jumao/status.json'}`);

  return lines.slice(0, 12).join('\n') + '\n';
}

function writeStatus(targetDir, status) {
  const dir = path.join(targetDir, '.jumao');
  fs.mkdirSync(dir, { recursive: true });
  const destination = statusPath(targetDir);
  const temporary = `${destination}.tmp-${process.pid}-${crypto.randomUUID()}`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(status, null, 2) + '\n', 'utf8');
    fs.renameSync(temporary, destination);
  } catch (error) {
    try { fs.rmSync(temporary, { force: true }); } catch {}
    throw error;
  }
  return status;
}

function makeStatus(targetDir, state, overrides = {}) {
  const cat = catStates[state] || catStates.sleeping;

  const status = {
    schemaVersion,
    jumaoVersion,
    updatedAt: new Date().toISOString(),
    workspace: workspaceInfo(targetDir),
    cat: {
      state,
      label: overrides.cat?.label || cat.label,
      message: overrides.cat?.message || cat.message
    },
    agentBoard: overrides.agentBoard || emptyAgentBoard(),
    blockers: overrides.blockers || [],
    nextSafeTask: overrides.nextSafeTask || cat.message,
    artifacts: {
      ...artifactPaths,
      ...(overrides.artifacts || {})
    },
    lastRun: overrides.lastRun || { command: null, target: null, ok: null }
  };

  if (overrides.planningRun) {
    const run = overrides.planningRun;
    Object.assign(status, {
      runId: run.runId,
      startedAt: run.startedAt,
      completedAt: run.completedAt ?? null,
      totalAgents: run.totalAgents,
      completedAgents: run.completedAgents,
      skippedAgents: run.skippedAgents,
      blockedAgents: run.blockedAgents,
      failedAgents: run.failedAgents,
      platformPending: run.platformPending || false,
      pendingDecision: run.pendingDecision || null
    });
  }

  return status;
}

function planningAgentBoard(groups) {
  const byId = new Map(groups.map((group) => [group.groupId, group]));
  const renderedGroups = agentGroups.map((group) => {
    const result = byId.get(group.id);
    const counts = result?.counts || { completed: 0, skipped: 0, blocked: 0, failed: 0 };
    const participatingAgentCount = counts.completed + counts.blocked + counts.failed;
    return {
      id: group.id,
      name: group.name,
      state: counts.failed > 0 || counts.blocked > 0
        ? 'blocked'
        : participatingAgentCount > 0
          ? 'triggered'
          : 'idle',
      triggeredAgentCount: participatingAgentCount,
      message: counts.failed > 0
        ? `${counts.failed} 项检查没能完成`
        : counts.blocked > 0
          ? `${counts.blocked} 项检查因为缺信息先停下了`
          : participatingAgentCount > 0
            ? `${counts.completed} 项检查已完成`
            : ''
    };
  });

  return {
    triggeredAgentCount: renderedGroups.reduce((sum, group) => sum + group.triggeredAgentCount, 0),
    activeGroupCount: renderedGroups.filter((group) => group.state !== 'idle').length,
    blockedGroupCount: renderedGroups.filter((group) => group.state === 'blocked').length,
    groups: renderedGroups
  };
}

function planningBlockers(run) {
  const blockers = [];
  for (const question of run.blockingQuestions || []) {
    blockers.push({
      title: '规划所需信息',
      message: question,
      source: '.jumao/intake-answers.json'
    });
  }
  if (run.error) {
    blockers.push({
      title: 'Agent 规划运行',
      message: run.error,
      source: run.runPath ? `${run.runPath}/manifest.json` : '.jumao/status.json'
    });
  }
  if (blockers.length === 0 && ((run.blockedAgents || 0) > 0 || (run.failedAgents || 0) > 0)) {
    blockers.push({
      title: 'Agent 规划运行',
      message: '检查时发现了问题。打开橘猫的详情，看看具体卡在哪一条。',
      source: run.runPath ? `${run.runPath}/manifest.json` : '.jumao/status.json'
    });
  }
  return blockers.slice(0, 3);
}

function sleepingStatus(targetDir) {
  return makeStatus(targetDir, 'sleeping', {
    nextSafeTask: '还没检查过。先在橘猫里做一次检查，看看项目现在的情况。',
    artifacts: {
      agentReport: null,
      agentFindings: '.jumao/status.json',
      codexGates: null
    }
  });
}

function workspaceInfo(targetDir) {
  return {
    name: readWorkspaceName(targetDir),
    path: path.resolve(targetDir)
  };
}

function readWorkspaceName(targetDir) {
  for (const file of ['README.zh-CN.md', 'README.md']) {
    const fullPath = path.join(targetDir, file);
    if (!fs.existsSync(fullPath)) continue;

    const firstHeading = fs.readFileSync(fullPath, 'utf8')
      .split('\n')
      .find((line) => line.startsWith('# '));
    if (firstHeading) return firstHeading.replace(/^#\s+/, '').trim();
  }

  return path.basename(path.resolve(targetDir));
}

function emptyAgentBoard() {
  return {
    triggeredAgentCount: 0,
    activeGroupCount: 0,
    blockedGroupCount: 0,
    groups: agentGroups.map((group) => ({
      id: group.id,
      name: group.name,
      state: 'idle',
      triggeredAgentCount: 0,
      message: ''
    }))
  };
}

function previousAgentBoard(targetDir, blockedGroupCount) {
  const previous = readExistingStatus(targetDir);
  const board = previous?.agentBoard || emptyAgentBoard();
  return {
    triggeredAgentCount: board.triggeredAgentCount || 0,
    activeGroupCount: board.activeGroupCount || 0,
    blockedGroupCount,
    groups: Array.isArray(board.groups) ? board.groups : emptyAgentBoard().groups
  };
}

function createAgentBoard(triggeredAgents, blockers) {
  const triggeredCounts = new Map();
  const blockerByGroupId = new Map();

  for (const agent of triggeredAgents) {
    triggeredCounts.set(agent.groupId, (triggeredCounts.get(agent.groupId) || 0) + 1);
  }

  for (const blocker of blockers) {
    if (blocker.groupId) blockerByGroupId.set(blocker.groupId, blocker);
  }

  const groups = agentGroups.map((group) => {
    const triggeredAgentCount = triggeredCounts.get(group.id) || 0;
    const blocker = blockerByGroupId.get(group.id);

    return {
      id: group.id,
      name: group.name,
      state: blocker ? 'blocked' : triggeredAgentCount > 0 ? 'triggered' : 'idle',
      triggeredAgentCount,
      message: blocker?.message || ''
    };
  });

  return {
    triggeredAgentCount: triggeredAgents.length,
    activeGroupCount: groups.filter((group) => group.state !== 'idle').length,
    blockedGroupCount: groups.filter((group) => group.state === 'blocked').length,
    groups
  };
}

function readExistingStatus(targetDir) {
  const file = statusPath(targetDir);
  if (!fs.existsSync(file)) return null;

  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function doctorBlockers(diagnosis) {
  const groups = new Map(diagnosis.triggeredGroups.map((group) => [group.id, group]));
  const blockers = new Map();

  for (const agent of diagnosis.triggeredAgents) {
    if (baseAgentIds.has(agent.id)) continue;
    if (blockers.has(agent.groupId)) continue;

    const group = groups.get(agent.groupId);
    blockers.set(agent.groupId, {
      groupId: agent.groupId,
      title: displayGroupName(group?.name || agent.groupId),
      message: groupMessages[agent.groupId] || agent.blockingRules?.[0] || '这一组发现了必须先处理的事，具体看下面的说明。',
      source: 'governance/codex-agent-gates.md'
    });
  }

  return Array.from(blockers.values());
}

function displayGroupName(name) {
  return name.replace(/\s*Agent\s*组$/i, '').trim();
}

function nextDoctorTask(blockers) {
  if (blockers.length === 0) {
    return '可以继续做一个小任务，但不能说可以上线。';
  }

  return `${blockers[0].message}。`;
}

function strictBlocker(error) {
  const separator = error.indexOf(': ');
  const source = separator === -1 ? 'jumao check --strict' : error.slice(0, separator);
  const reason = separator === -1 ? error : error.slice(separator + 2);

  return {
    title: strictTitle(source),
    message: strictMessage(source, reason),
    source
  };
}

function strictTitle(source) {
  if (source.includes('product-brief')) return '产品简报';
  if (source.includes('scope-gate')) return '首版范围';
  if (source.includes('screen-states')) return '页面状态';
  if (source.includes('data-safety')) return '数据安全';
  if (source.includes('release-proof')) return '完成证据';
  if (source.includes('AGENTS')) return 'Agent 规则';
  if (source.includes('CLAUDE')) return 'Claude 规则';
  return '严格门禁';
}

function strictMessage(source, reason) {
  if (source.includes('product-brief')) return '先补清楚用户、目标和成功证据';
  if (source.includes('scope-gate')) return '先补首版必须做和明确不做';
  if (source.includes('screen-states')) return '先补加载、空状态、错误和成功状态';
  if (source.includes('data-safety')) return '先补数据保存、删除和第三方工具边界';
  return reason;
}

function nextStrictTask(strictResult) {
  if (strictResult.errors.length === 0) {
    return '可以继续生成任务包。';
  }

  return `${strictBlocker(strictResult.errors[0]).message}。`;
}

function agentBoardLine(agentBoard = emptyAgentBoard()) {
  if (!agentBoard.activeGroupCount && !agentBoard.blockedGroupCount) {
    return '检查小组：还没开始';
  }

  return `检查小组：${agentBoard.activeGroupCount} 组在工作，${agentBoard.blockedGroupCount} 组遇到要紧事停下了`;
}
