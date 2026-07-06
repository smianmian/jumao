import fs from 'node:fs';
import path from 'node:path';
import { requiredProductFiles, validateStrictWorkspace } from './strict-check.js';

const coreProductFiles = [
  'product/product-brief.zh-CN.md',
  'product/scope-gate.zh-CN.md',
  'product/screen-states.zh-CN.md',
  'product/data-safety.zh-CN.md'
];

export function auditWorkspace(targetDir) {
  if (!isValidJumaoWorkspace(targetDir)) {
    return {
      ok: false,
      message: `${targetDir} is not a valid Jumao workspace. Run jumao new first.`
    };
  }

  const strictResult = validateStrictWorkspace(targetDir);
  const report = formatAuditReport(targetDir, strictResult);
  return {
    ok: true,
    report,
    strictResult
  };
}

function isValidJumaoWorkspace(targetDir) {
  if (!fs.existsSync(targetDir)) return false;
  if (!fs.statSync(targetDir).isDirectory()) return false;

  const markers = [
    'product',
    'proof',
    'AGENTS.md',
    'CLAUDE.md',
    ...requiredProductFiles
  ];
  return markers.some((marker) => fs.existsSync(path.join(targetDir, marker)));
}

function formatAuditReport(targetDir, strictResult) {
  const findings = [
    ...strictResult.errors.map((gap) => ({ level: 'error', ...parseGap(gap) })),
    ...strictResult.warnings.map((gap) => ({ level: 'warning', ...parseGap(gap) }))
  ];
  const status = workspaceStatus(strictResult);
  const strictGate = strictResult.errors.length === 0 ? 'passed' : 'failed';
  const nextStep = recommendedNextStep(strictResult);

  return [
    `Jumao audit report for ${targetDir}`,
    '',
    'Summary:',
    `- Workspace status: ${status}`,
    `- Strict gate: ${strictGate}`,
    `- Main gaps: ${findings.length}`,
    `- Recommended next step: ${nextStep}`,
    '',
    'Findings:',
    findings.length > 0 ? findings.map(formatFinding).join('\n\n') : '- No gaps found.',
    '',
    'Next safe task for AI:',
    nextSafeTask(strictResult),
    '',
    'Do not do yet:',
    ...doNotDoYet(strictResult).map((item) => `- ${item}`)
  ].join('\n') + '\n';
}

function workspaceStatus(strictResult) {
  if (strictResult.errors.length > 0) return 'not ready';
  if (strictResult.warnings.length > 0) return 'planning ready, not release ready';
  return 'ready';
}

function recommendedNextStep(strictResult) {
  if (strictResult.errors.length > 0) {
    return 'Fill the first missing core product file before asking AI to code.';
  }
  if (strictResult.warnings.length > 0) {
    return 'Keep planning work local, and fill completion proof before release claims.';
  }
  return 'Hand the task pack to an AI coding tool for a small implementation step.';
}

function nextSafeTask(strictResult) {
  if (strictResult.errors.length > 0) {
    const firstCoreGap = strictResult.errors.find((gap) => coreProductFiles.some((file) => gap.startsWith(`${file}:`)));
    const parsed = parseGap(firstCoreGap || strictResult.errors[0]);
    return `Update ${parsed.file} to resolve: ${parsed.reason}.`;
  }
  if (strictResult.warnings.length > 0) {
    return 'Continue implementation planning, but ask AI to keep release proof marked incomplete.';
  }
  return 'Ask AI to implement one small scoped task from the filled product files.';
}

function doNotDoYet(strictResult) {
  if (strictResult.errors.length > 0) {
    return [
      'Do not start implementation before product gaps are fixed.',
      'Do not add unrequested features to fill unclear scope.',
      'Do not publish, push, or call paid APIs.'
    ];
  }

  if (strictResult.warnings.length > 0) {
    return [
      'Do not claim the work is complete or release-ready.',
      'Do not publish, push, or call paid APIs.'
    ];
  }

  return ['Do not publish, push, or call paid APIs without human confirmation.'];
}

function formatFinding(finding) {
  return [
    `- [${finding.level}] ${finding.file}: ${finding.reason}`,
    `  Why it matters: ${whyItMatters(finding)}`,
    `  Next action: ${nextAction(finding)}`
  ].join('\n');
}

function parseGap(gap) {
  const separator = gap.indexOf(': ');
  if (separator === -1) {
    return { file: 'workspace', reason: gap };
  }

  return {
    file: gap.slice(0, separator),
    reason: gap.slice(separator + 2)
  };
}

function whyItMatters(finding) {
  if (finding.level === 'warning') {
    return 'AI may confuse planning progress with release completion.';
  }
  if (finding.file.includes('product-brief')) {
    return 'AI may guess the user, goal, or success criteria.';
  }
  if (finding.file.includes('scope-gate')) {
    return 'AI may add features outside the first version.';
  }
  if (finding.file.includes('screen-states')) {
    return 'AI may only build the happy path and miss edge states.';
  }
  if (finding.file.includes('data-safety')) {
    return 'AI may choose unsafe data collection or storage defaults.';
  }
  return 'AI may work from incomplete project context.';
}

function nextAction(finding) {
  if (finding.level === 'warning') {
    return 'Fill proof after implementation, or keep it clearly marked as incomplete.';
  }
  if (finding.file.includes('product-brief')) {
    return 'Write concrete users, first-version goal, evidence, and risk boundaries.';
  }
  if (finding.file.includes('scope-gate')) {
    return 'Add specific do, do-not-do, and human-confirmation bullets.';
  }
  if (finding.file.includes('screen-states')) {
    return 'Add one real page row with loading, empty, error, success, and permission states.';
  }
  if (finding.file.includes('data-safety')) {
    return 'State collected data, avoided data, third parties, deletion, and retention.';
  }
  return 'Restore or fill this required workspace file.';
}
