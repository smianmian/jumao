import fs from 'node:fs';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as defaultInput, stdout as defaultOutput } from 'node:process';
import { validateStrictWorkspace } from './strict-check.js';
import { validateCoreFile } from './validators.js';

export const interviewSchema = JSON.parse(
  fs.readFileSync(new URL('./interview-schema.json', import.meta.url), 'utf8')
);

const coreFiles = [
  'product/product-brief.zh-CN.md',
  'product/scope-gate.zh-CN.md',
  'product/screen-states.zh-CN.md',
  'product/data-safety.zh-CN.md'
];

export async function collectInterviewAnswers(input = defaultInput, output = defaultOutput) {
  const rl = createInterface({ input, output });
  try {
    const answers = {};
    for (const question of interviewSchema.questions) {
      const value = await rl.question(`${question.title} `);
      setAnswerAtPath(
        answers,
        question.answerPath,
        question.inputType === 'list' ? splitList(value) : value
      );
    }
    return answers;
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

function setAnswerAtPath(answers, answerPath, value) {
  const parts = answerPath.split('.');
  const key = parts.pop();
  const target = parts.reduce((current, part) => current[part] ||= {}, answers);
  target[key] = value;
}

function bulletList(items) {
  return items.map((item) => `- ${item}`).join('\n');
}

function listSentence(items) {
  return items.join('、');
}
