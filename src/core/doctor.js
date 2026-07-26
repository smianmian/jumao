import fs from 'node:fs';
import path from 'node:path';
import { agentGroups, getTriggeredAgents } from './agent-registry.js';
import { writeCheckingStatus, writeCommandBlockedStatus, writeDoctorStatus } from './status.js';
import { createLineReader } from './interview.js';

const governanceFiles = {
  report: 'governance/agent-review-report.md',
  findings: 'governance/agent-findings.json',
  gates: 'governance/codex-agent-gates.md'
};

const codexGateRules = [
  '没有 DATA_GOVERNANCE_REGISTER.md，不得新增数据库字段。',
  '没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。',
  '没有 HEALTH_CLAIMS_APPROVAL_LOG.md，不得新增健康结论、推送文案、报告文案。',
  '没有 IAP_REVENUE_OPS_CHECKLIST.md，不得接入 StoreKit 生产订阅。',
  '没有 CLOUD_IAM_SECRETS_BACKUP_SPEC.md，不得部署生产环境。',
  '没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。',
  '没有 SUPPORT_REFUND_DELETION_PLAYBOOK.md，不得上线带登录和订阅的版本。',
  '没有 SCREEN_INVENTORY.md 和 STATE_MATRIX.md，不得写 SwiftUI 页面。',
  '没有 ORG_ROLE_OWNER_MATRIX.md，不得开始业务代码。'
];

export const doctorInterviewQuestions = [
  {
    key: 'stage',
    title: '这个产品现在做到哪一步了？',
    options: [
      { label: '还在自己试', values: { projectStage: 'prototype', launchIntent: 'private' } },
      { label: '已经给几个人用了', values: { projectStage: 'internal_test', launchIntent: 'private' } },
      { label: '准备正式给大家用', values: { projectStage: 'ready_to_release', launchIntent: 'public_launch' } },
      { label: '还没想好', values: { projectStage: 'prototype', launchIntent: 'private' } }
    ]
  },
  {
    key: 'store',
    title: '打算放到应用商店让别人自己下载吗？',
    options: [
      { label: '只装自己的设备', values: { storePlan: 'none' } },
      { label: '先给少数人试用', values: { storePlan: 'testflight' } },
      { label: '要正式上架 App Store', values: { storePlan: 'app_store' } },
      { label: '还没想好', values: { storePlan: 'none' } }
    ]
  },
  {
    key: 'login',
    title: '要不要别人登录才能用？',
    options: [
      { label: '要登录', values: { loginNeeded: true } },
      { label: '不用登录', values: { loginNeeded: false } },
      { label: '还没想好', values: { loginNeeded: false } }
    ]
  },
  {
    key: 'charging',
    title: '要不要收钱？',
    options: [
      { label: '不收费', values: { chargingPlan: 'free' } },
      { label: '一次买断', values: { chargingPlan: 'paid' } },
      { label: '按月或按年会员', values: { chargingPlan: 'subscription' } },
      { label: '还没想好', values: { chargingPlan: 'free' } }
    ]
  },
  {
    key: 'crossDevice',
    title: '用户换了手机，里面的东西要不要还在？',
    options: [
      { label: '要还在', values: { crossDeviceData: 'needed' } },
      { label: '丢了不要紧', values: { crossDeviceData: 'local_only' } },
      { label: '还没想好', values: { crossDeviceData: 'local_only' } }
    ]
  },
  {
    key: 'sensitive',
    title: '它会碰到需要特别小心的内容吗？可多选，用逗号隔开数字。',
    multi: true,
    listKey: 'sensitiveData',
    options: [
      { label: '健康', item: 'health' },
      { label: '孩子', item: 'children' },
      { label: '钱或理财', item: 'payment' },
      { label: '位置', item: 'location' },
      { label: '都不涉及', item: null }
    ]
  },
  {
    key: 'china',
    title: '用它的人主要在中国大陆吗？',
    options: [
      { label: '主要在大陆', values: { chinaUsers: true } },
      { label: '主要在海外', values: { chinaUsers: false } },
      { label: '大陆海外都有', values: { chinaUsers: true } },
      { label: '还没想好', values: { chinaUsers: false } }
    ]
  }
];

export async function collectDoctorAnswers(input, output) {
  const reader = createLineReader(input, output);
  try {
    output.write('回答下面几道普通问题，橘猫就能给项目做一次体检。\n\n');
    const answers = {};
    for (const question of doctorInterviewQuestions) {
      output.write(`${question.title}\n`);
      question.options.forEach((option, index) => output.write(`  ${index + 1}) ${option.label}\n`));
      const picked = await pickDoctorOptions(reader, output, question);
      if (!picked.ok) return picked;
      if (question.multi) {
        answers[question.listKey] = picked.items;
      } else {
        Object.assign(answers, picked.values);
      }
    }
    answers.ownerType = 'personal';
    answers.supportNeeds = derivedSupportNeeds(answers);
    return { ok: true, answers };
  } finally {
    reader.close();
  }
}

async function pickDoctorOptions(reader, output, question) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const line = await reader.ask('> ');
    if (line === null) return { ok: false, message: '回答中断了，先想好再重新运行。' };
    const numbers = line.split(/[,，、\s]+/).filter(Boolean);
    const validSelection = numbers.length > 0
      && numbers.every((item) => /^\d+$/.test(item) && question.options[Number(item) - 1]);
    if (validSelection && (question.multi || numbers.length === 1)) {
      if (question.multi) {
        const items = [...new Set(numbers.map((item) => question.options[Number(item) - 1].item))]
          .filter((item) => item !== null);
        return { ok: true, items };
      }
      return { ok: true, values: question.options[Number(numbers[0]) - 1].values };
    }
    if (attempt === 0) {
      output.write(question.multi ? '输入选项前面的数字就行，多个用逗号隔开。\n' : '输入选项前面的数字就行。\n');
    }
  }
  return { ok: false, message: `「${question.title}」还没有回答，先想好再重新运行。` };
}

function derivedSupportNeeds(answers) {
  const needs = [];
  if (answers.loginNeeded) needs.push('account');
  if (answers.chargingPlan === 'paid' || answers.chargingPlan === 'subscription') needs.push('refund');
  if (answers.crossDeviceData === 'needed' || (answers.sensitiveData || []).length > 0) needs.push('deletion');
  return needs;
}

export function runDoctor(targetDir, options = {}) {
  const answersFile = options.answersFile;

  if (!isJumaoWorkspace(targetDir)) {
    return {
      ok: false,
      message: `${targetDir} 不是 Jumao workspace。请先运行 jumao new。`
    };
  }

  if (options.write) writeCheckingStatus(targetDir, { command: 'doctor', target: null });

  let answerValues;
  if (options.answers && typeof options.answers === 'object') {
    answerValues = options.answers;
  } else {
    if (!answersFile || !fs.existsSync(answersFile)) {
      if (options.write) {
        writeCommandBlockedStatus(targetDir, { command: 'doctor', target: null }, 'answers 文件不存在');
      }
      return {
        ok: false,
        message: `answers 文件不存在: ${answersFile || '(missing --answers)'}`
      };
    }

    const answers = readJsonFile(answersFile);
    if (!answers.ok) {
      if (options.write) {
        writeCommandBlockedStatus(targetDir, { command: 'doctor', target: null }, 'answers 文件不是有效 JSON');
      }
      return answers;
    }
    answerValues = answers.value;
  }

  const diagnosis = buildDoctorDiagnosis(targetDir, answerValues);
  if (options.write) {
    writeGovernanceFiles(targetDir, diagnosis);
    writeDoctorStatus(targetDir, diagnosis);
  }

  return {
    ok: true,
    report: diagnosis.report,
    diagnosis,
    writtenFiles: options.write ? Object.values(governanceFiles) : []
  };
}

export function buildDoctorDiagnosis(targetDir, answers) {
  const triggeredAgents = getTriggeredAgents(answers);
  const triggeredGroupIds = unique(triggeredAgents.map((agent) => agent.groupId));
  const triggeredGroups = agentGroups.filter((group) => triggeredGroupIds.includes(group.id));
  const inferredNeeds = unique(triggeredAgents.flatMap((agent) => agent.inferredNeeds));
  const notSure = hasNotSureAnswer(answers);
  const report = renderDoctorReport({
    targetDir,
    answers,
    triggeredAgents,
    triggeredGroups,
    inferredNeeds,
    notSure
  });

  return {
    targetDir,
    answers,
    triggeredGroups,
    triggeredAgents,
    inferredNeeds,
    codexGateRules,
    notSure,
    report,
    codexGates: renderCodexGates(triggeredAgents)
  };
}

function readJsonFile(file) {
  try {
    return {
      ok: true,
      value: JSON.parse(fs.readFileSync(file, 'utf8'))
    };
  } catch (error) {
    return {
      ok: false,
      message: `answers 文件不是有效 JSON: ${error.message}`
    };
  }
}

function isJumaoWorkspace(targetDir) {
  if (!fs.existsSync(targetDir)) return false;
  if (!fs.statSync(targetDir).isDirectory()) return false;

  return fs.existsSync(path.join(targetDir, 'product')) &&
    (fs.existsSync(path.join(targetDir, 'AGENTS.md')) || fs.existsSync(path.join(targetDir, 'CLAUDE.md')));
}

function writeGovernanceFiles(targetDir, diagnosis) {
  const governanceDir = path.join(targetDir, 'governance');
  fs.mkdirSync(governanceDir, { recursive: true });
  fs.writeFileSync(path.join(targetDir, governanceFiles.report), diagnosis.report, 'utf8');
  fs.writeFileSync(path.join(targetDir, governanceFiles.findings), renderFindingsJson(diagnosis), 'utf8');
  fs.writeFileSync(path.join(targetDir, governanceFiles.gates), diagnosis.codexGates, 'utf8');
}

function renderDoctorReport(context) {
  return [
    '# Jumao doctor 诊断',
    '',
    '## 你现在处于什么阶段',
    describeProjectStage(context.answers, context.notSure),
    '',
    '## 我帮你补一下认知',
    bulletList(educationItems(context.answers, context.notSure)),
    '',
    '## 你可能需要什么',
    bulletList(context.inferredNeeds.slice(0, 24)),
    '',
    '## 现在可以先不做什么',
    bulletList(deferItems(context.answers)),
    '',
    '## 下一步最小安全任务',
    nextSafeTask(context.notSure),
    '',
    '## 触发了哪些 Agent 组',
    bulletList(context.triggeredGroups.map((group) => group.name)),
    '',
    '## 触发了哪些关键 Agent',
    bulletList(context.triggeredAgents.map((agent) => agent.name)),
    '',
    '## 给 Codex 的硬门禁',
    bulletList(codexGateRules)
  ].join('\n') + '\n';
}

function renderCodexGates(triggeredAgents) {
  const agentRules = unique(triggeredAgents.flatMap((agent) => agent.codexRules));

  return [
    '# Codex Agent Gates',
    '',
    '## 核心硬门禁',
    bulletList(codexGateRules),
    '',
    '## 本次触发 Agent 补充规则',
    bulletList(agentRules)
  ].join('\n') + '\n';
}

function renderFindingsJson(diagnosis) {
  return JSON.stringify({
    targetDir: diagnosis.targetDir,
    answers: diagnosis.answers,
    notSure: diagnosis.notSure,
    triggeredGroups: diagnosis.triggeredGroups.map((group) => ({
      id: group.id,
      name: group.name
    })),
    triggeredAgents: diagnosis.triggeredAgents.map((agent) => ({
      id: agent.id,
      name: agent.name,
      groupId: agent.groupId,
      plainName: agent.plainName,
      inferredNeeds: agent.inferredNeeds,
      requiredFiles: agent.requiredFiles,
      blockingRules: agent.blockingRules,
      codexRules: agent.codexRules
    })),
    inferredNeeds: diagnosis.inferredNeeds,
    codexGateRules
  }, null, 2) + '\n';
}

function describeProjectStage(answers, notSure) {
  if (notSure) {
    return '现在不需要一次决定清楚，我会先按低风险路径处理。';
  }

  const parts = [];
  if (answers.launchIntent === 'public_launch') parts.push('准备公开上线');
  if (answers.storePlan === 'app_store') parts.push('准备上 App Store');
  if (answers.ownerType === 'company') parts.push('公司主体项目');
  if (answers.chargingPlan === 'subscription' || answers.chargingPlan === 'paid') parts.push('商业收费');
  if (answers.projectStage === 'prototype') parts.push('原型阶段');
  if (answers.projectStage === 'internal_test') parts.push('内测阶段');
  if (answers.projectStage === 'ready_to_release') parts.push('准备发布阶段');

  if (parts.length === 0) return '早期规划阶段。';
  return `${parts.join('、')}。`;
}

function educationItems(answers, notSure) {
  const items = [];

  if (notSure) {
    items.push('现在不需要一次决定清楚，我会先按低风险路径处理。');
  }

  if (answers.loginNeeded || answers.crossDeviceData === 'needed' || hasAny(answers.supportNeeds, ['account', 'deletion'])) {
    items.push('如果你要登录、换机恢复、客服处理账号问题，通常会出现账号、数据保存和后台处理需求。你不用先懂这些，我会先标成可能需要。');
  }

  if (answers.storePlan === 'app_store' || answers.storePlan === 'testflight') {
    items.push('如果你要上 App Store，通常需要开发者账号、审核材料、隐私政策、支持入口和测试账号。');
  }

  if (answers.chargingPlan === 'subscription' || answers.chargingPlan === 'paid') {
    items.push('如果你做 iOS 数字会员，通常会涉及 Apple 内购、权益、退款、恢复购买和对账。');
  }

  if (hasAny(answers.sensitiveData, ['health'])) {
    items.push('如果碰健康数据，要先讲清隐私、数据删除、第三方工具和健康声明边界。');
  }

  if (answers.chinaUsers) {
    items.push('如果面向中国大陆用户，可能要考虑官网、备案、隐私链接和主体一致。');
  }

  if (items.length === 0) {
    items.push('现在先把项目目标、首版范围、页面状态和数据边界讲清楚，就能降低 AI 跑偏风险。');
  }

  return items;
}

function deferItems(answers) {
  const items = [
    '生产支付',
    '生产后台',
    '第三方 SDK',
    '数据库字段'
  ];

  if (hasAny(answers.sensitiveData, ['health'])) items.splice(3, 0, '健康结论文案');
  return items;
}

function nextSafeTask(notSure) {
  if (notSure) {
    return '先补产品范围、页面状态和数据边界，不急着决定上线或收费。';
  }

  return '先补产品范围、页面状态、数据边界、账号和收费决策。';
}

function hasNotSureAnswer(value) {
  if (Array.isArray(value)) return value.some((item) => item === 'not_sure');
  if (value && typeof value === 'object') return Object.values(value).some(hasNotSureAnswer);
  return value === 'not_sure';
}

function hasAny(value, expected) {
  const values = Array.isArray(value) ? value : [value];
  return values.some((item) => expected.includes(item));
}

function unique(items) {
  return [...new Set(items.filter(Boolean))];
}

function bulletList(items) {
  if (items.length === 0) return '- 暂无';
  return items.map((item) => `- ${item}`).join('\n');
}
