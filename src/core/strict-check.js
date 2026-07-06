import fs from 'node:fs';
import path from 'node:path';
import { isCompletionProofFilled, validateCoreFile } from './validators.js';

export const requiredProductFiles = [
  'product/product-brief.zh-CN.md',
  'product/scope-gate.zh-CN.md',
  'product/screen-states.zh-CN.md',
  'product/data-safety.zh-CN.md',
  'proof/release-proof.zh-CN.md',
  'AGENTS.md',
  'CLAUDE.md'
];

const strictContentFiles = requiredProductFiles.filter(
  (file) => file.startsWith('product/') || file.startsWith('proof/')
);

const coreContentFiles = strictContentFiles.filter((file) => file.startsWith('product/'));
const completionProofFile = 'proof/release-proof.zh-CN.md';

export function validateStrictWorkspace(targetDir) {
  const missing = missingRequiredFiles(targetDir);
  const result = {
    errors: missing.map((file) => `${file}: missing required file`),
    warnings: []
  };

  for (const file of ['AGENTS.md', 'CLAUDE.md']) {
    const fullPath = path.join(targetDir, file);
    if (fs.existsSync(fullPath) && fs.readFileSync(fullPath, 'utf8').trim().length === 0) {
      result.errors.push(`${file}: file is empty`);
    }
  }

  for (const file of coreContentFiles) {
    const fullPath = path.join(targetDir, file);
    if (!fs.existsSync(fullPath)) continue;

    const text = fs.readFileSync(fullPath, 'utf8');
    for (const error of validateCoreFile(file, text)) result.errors.push(`${file}: ${error}`);
  }

  const proofPath = path.join(targetDir, completionProofFile);
  if (fs.existsSync(proofPath)) {
    const proofText = fs.readFileSync(proofPath, 'utf8');
    if (!isCompletionProofFilled(proofText)) {
      result.warnings.push(`${completionProofFile}: completion proof is not filled yet`);
    }
  }

  return result;
}

export function missingRequiredFiles(targetDir) {
  return requiredProductFiles.filter((file) => !fs.existsSync(path.join(targetDir, file)));
}
