import fs from 'node:fs';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as defaultInput, stdout as defaultOutput } from 'node:process';
import { validateStrictWorkspace } from './strict-check.js';
import { validateCoreFile } from './validators.js';

const coreFiles = [
  'product/product-brief.zh-CN.md',
  'product/scope-gate.zh-CN.md',
  'product/screen-states.zh-CN.md',
  'product/data-safety.zh-CN.md'
];

export async function collectInterviewAnswers(input = defaultInput, output = defaultOutput) {
  const rl = createInterface({ input, output });
  try {
    return {
      primaryUser: await rl.question('主要用户是谁？ '),
      firstVersionGoal: await rl.question('第一版先证明什么？ '),
      userCanDo: await rl.question('用户能完成什么？ '),
      successEvidence: await rl.question('你能看到什么成功证据？ '),
      cannotPromise: await rl.question('不能承诺什么？ '),
      cannotCollect: await rl.question('不能收集什么？ '),
      humanConfirmActions: splitList(await rl.question('哪些动作必须人工确认？用逗号分隔。 ')),
      mustDo: splitList(await rl.question('首版必须做什么？用逗号分隔。 ')),
      wontDo: splitList(await rl.question('首版明确不做什么？用逗号分隔。 ')),
      aiMustNotAdd: splitList(await rl.question('不要让 AI 自己加什么？用逗号分隔。 ')),
      mainScreen: {
        name: await rl.question('主页面或主流程名称？ '),
        userGoal: await rl.question('用户在这个页面想做什么？ '),
        loading: await rl.question('加载中怎么显示？ '),
        empty: await rl.question('空状态怎么显示？ '),
        error: await rl.question('错误状态怎么显示？ '),
        success: await rl.question('成功状态怎么显示？ '),
        permissionDenied: await rl.question('权限拒绝怎么显示？不涉及也请写“不涉及”。 ')
      },
      dataSafety: {
        collects: await rl.question('收集哪些数据？不收集就写“首版不收集用户数据”。 '),
        doesNotCollect: await rl.question('明确不收集哪些数据？ '),
        thirdParties: await rl.question('第三方服务是什么？没有就写“首版不使用第三方服务”。 '),
        deletion: await rl.question('用户如何删除数据？ '),
        retention: await rl.question('删除后是否保留数据？没有就写“删除后无保留数据”。 ')
      }
    };
  } finally {
    rl.close();
  }
}

export function readAnswersFile(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export function runInterview(targetDir, answers, options = {}) {
  const force = options.force === true;
  const filledFiles = filledCoreFiles(targetDir);

  if (!force && filledFiles.length > 0) {
    return {
      ok: false,
      message: `Core files already have valid content: ${filledFiles.join(', ')}. Re-run with --force to overwrite.`
    };
  }

  const files = renderCoreFiles(answers);
  for (const [file, text] of Object.entries(files)) {
    const fullPath = path.join(targetDir, file);
    fs.mkdirSync(path.dirname(fullPath), { recursive: true });
    fs.writeFileSync(fullPath, text, 'utf8');
  }

  return {
    ok: true,
    writtenFiles: Object.keys(files),
    strictResult: validateStrictWorkspace(targetDir)
  };
}

function filledCoreFiles(targetDir) {
  return coreFiles.filter((file) => {
    const fullPath = path.join(targetDir, file);
    if (!fs.existsSync(fullPath)) return false;
    const text = fs.readFileSync(fullPath, 'utf8');
    return validateCoreFile(file, text).length === 0;
  });
}

function renderCoreFiles(answers) {
  return {
    'product/product-brief.zh-CN.md': renderProductBrief(answers),
    'product/scope-gate.zh-CN.md': renderScopeGate(answers),
    'product/screen-states.zh-CN.md': renderScreenStates(answers),
    'product/data-safety.zh-CN.md': renderDataSafety(answers)
  };
}

function renderProductBrief(answers) {
  return [
    '# 产品简报',
    '',
    `主要用户：${answers.primaryUser}`,
    `第一版先证明一件事：${answers.firstVersionGoal}`,
    `用户能完成：${answers.userCanDo}`,
    `我们能看到的证据：${answers.successEvidence}`,
    `不能承诺：${answers.cannotPromise}`,
    `不能收集：${answers.cannotCollect}`,
    `会影响真实用户或钱的动作：${listSentence(answers.humanConfirmActions)}`
  ].join('\n') + '\n';
}

function renderScopeGate(answers) {
  return [
    '# 范围门禁',
    '',
    '## 首版必须做',
    bulletList(answers.mustDo),
    '',
    '## 首版明确不做',
    bulletList(answers.wontDo),
    '',
    '## 不要让 AI 自己加',
    bulletList(answers.aiMustNotAdd),
    '',
    '## 需要人工确认的动作',
    bulletList(answers.humanConfirmActions)
  ].join('\n') + '\n';
}

function renderScreenStates(answers) {
  const screen = answers.mainScreen;
  return [
    '# 页面状态',
    '',
    '| 页面 | 用户想做什么 | 加载中 | 空状态 | 错误状态 | 成功状态 | 权限拒绝 |',
    '|---|---|---|---|---|---|---|',
    `| ${screen.name} | ${screen.userGoal} | ${screen.loading} | ${screen.empty} | ${screen.error} | ${screen.success} | ${screen.permissionDenied} |`
  ].join('\n') + '\n';
}

function renderDataSafety(answers) {
  const data = answers.dataSafety;
  return [
    '# 数据安全',
    '',
    `${data.collects}。`,
    `${data.thirdParties}。`,
    `${data.doesNotCollect}。`,
    `${data.deletion}。`,
    `${data.retention}。`
  ].join('\n') + '\n';
}

function splitList(value) {
  return value
    .split(/[，,、]/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function bulletList(items) {
  return items.map((item) => `- ${item}`).join('\n');
}

function listSentence(items) {
  return items.join('、');
}
