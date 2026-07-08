import fs from 'node:fs';
import path from 'node:path';
import { requiredProductFiles, validateStrictWorkspace } from './strict-check.js';

const targets = new Set(['codex', 'claude', 'cursor']);

const targetRules = {
  codex: [
    'Read AGENTS.md first.',
    'Do not modify files outside the requested scope.',
    'Run tests before reporting completion.',
    'Report changed / not changed / test result / remaining gaps.'
  ],
  claude: [
    'Read CLAUDE.md first.',
    'Keep implementation scoped.',
    'Explain assumptions before large changes.'
  ],
  cursor: [
    'Keep edits small.',
    'Prefer existing project structure.',
    'Do not create new architecture unless asked.'
  ]
};

export function packDefaultWorkspace(targetDir) {
  const sections = [];
  for (const file of requiredProductFiles.filter((item) => item.endsWith('.md'))) {
    const fullPath = path.join(targetDir, file);
    if (fs.existsSync(fullPath)) {
      sections.push(`\n\n## ${file}\n\n${fs.readFileSync(fullPath, 'utf8').trim()}`);
    }
  }

  if (sections.length === 0) {
    return {
      ok: false,
      message: 'No product files found. Run jumao new first.'
    };
  }

  const outputPath = path.join(targetDir, 'jumao-task-pack.md');
  const taskPack = [
    '# 橘猫 AI 任务包',
    '',
    '把这份文件交给你的 AI 编程工具。先让它总结目标、缺口和下一步安全动作。',
    sections.join('')
  ].join('\n') + '\n';

  fs.writeFileSync(outputPath, taskPack, 'utf8');
  return {
    ok: true,
    outputPath
  };
}

export function packTargetWorkspace(targetDir, target) {
  if (!targets.has(target)) {
    return {
      ok: false,
      message: `Unknown pack target: ${target}. Use codex, claude, or cursor.`
    };
  }

  const strictResult = validateStrictWorkspace(targetDir);
  if (strictResult.errors.length > 0) {
    return {
      ok: false,
      strictResult,
      message: [
        `Jumao target pack blocked because strict gate failed for ${targetDir}.`,
        'Run:',
        `- jumao audit ${targetDir}`,
        `- jumao interview ${targetDir}`
      ].join('\n')
    };
  }

  const outputPath = path.join(targetDir, 'tasks', `${target}-task-pack.md`);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, renderTargetPack(targetDir, target, strictResult), 'utf8');
  return {
    ok: true,
    outputPath
  };
}

function renderTargetPack(targetDir, target, strictResult) {
  return [
    `# Jumao ${target} task pack`,
    '',
    '## Project summary',
    `Workspace: ${targetDir}`,
    `Target tool: ${target}`,
    '',
    '## Product brief',
    readWorkspaceFile(targetDir, 'product/product-brief.zh-CN.md'),
    '',
    '## Scope gate',
    readWorkspaceFile(targetDir, 'product/scope-gate.zh-CN.md'),
    '',
    '## Screen states',
    readWorkspaceFile(targetDir, 'product/screen-states.zh-CN.md'),
    '',
    '## Data safety',
    readWorkspaceFile(targetDir, 'product/data-safety.zh-CN.md'),
    '',
    '## Release proof status',
    releaseProofStatus(targetDir, strictResult),
    '',
    '## AI execution rules',
    aiExecutionRules(target).map((rule) => `- ${rule}`).join('\n'),
    agentReviewBoardGates(targetDir),
    '',
    '## First safe task',
    firstSafeTask(strictResult),
    '',
    '## Do not do yet',
    doNotDoYet(strictResult).map((item) => `- ${item}`).join('\n')
  ].join('\n') + '\n';
}

function readWorkspaceFile(targetDir, file) {
  const fullPath = path.join(targetDir, file);
  if (!fs.existsSync(fullPath)) return '(missing)';
  return fs.readFileSync(fullPath, 'utf8').trim();
}

function releaseProofStatus(targetDir, strictResult) {
  if (strictResult.warnings.length > 0) {
    return strictResult.warnings.map((warning) => `Warning: ${warning}`).join('\n');
  }

  return readWorkspaceFile(targetDir, 'proof/release-proof.zh-CN.md');
}

function agentReviewBoardGates(targetDir) {
  const gates = readWorkspaceFile(targetDir, 'governance/codex-agent-gates.md');
  if (gates === '(missing)') return '';

  return [
    '',
    '# Agent Review Board Gates',
    '',
    gates
  ].join('\n');
}

function aiExecutionRules(target) {
  return [
    'Work only from this task pack and the referenced product files.',
    'Keep implementation scoped to the first version.',
    'Ask before publishing, pushing, deleting user files, or calling paid APIs.',
    ...targetRules[target]
  ];
}

function firstSafeTask(strictResult) {
  if (strictResult.warnings.length > 0) {
    return 'Implement one small scoped task from the product files; keep release proof marked incomplete until verified.';
  }
  return 'Implement one small scoped task from the product files, then update completion proof with verification results.';
}

function doNotDoYet(strictResult) {
  const items = [
    'Do not publish, push, or call paid APIs without human confirmation.',
    'Do not add features outside the scope gate.',
    'Do not create new architecture unless explicitly requested.'
  ];

  if (strictResult.warnings.length > 0) {
    items.unshift('Do not claim the work is complete or release-ready.');
  }

  return items;
}
