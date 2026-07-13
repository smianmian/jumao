const placeholderTerms = [
  'TODO',
  'TBD',
  'placeholder',
  'fill in',
  'to be filled',
  '待填写',
  '请填写',
  '未填写',
  '待补充',
  '稍后补充',
  '以后再说',
  '后面再说',
  '先空着',
  '暂无',
  '无内容',
  '写一下',
  '随便写',
  '已填写',
  '测试',
  '示例',
  '占位',
  '???',
  'xxx',
  '...',
  '——'
];

const lowQualityLines = new Set([
  '已填写',
  '已填写。',
  '做一个app',
  '做一个app。',
  '做一个网站',
  '做一个网站。',
  '做一个小工具',
  '做一个小工具。',
  '用户都可以用',
  '用户都可以用。',
  '越多人越好',
  '越多人越好。',
  '先上线再说',
  '先上线再说。',
  '后面再补',
  '后面再补。',
  '无',
  '无。',
  '没有',
  '没有。',
  '测试',
  '测试。'
]);

const productBriefRequiredLabels = [
  '主要用户',
  '第一版先证明一件事',
  '用户能完成'
];

const scopeRequiredSections = [
  '首版必须做',
  '首版明确不做'
];

const screenRequiredColumns = ['页面', '用户想做什么'];

export function validateCoreFile(file, text) {
  const errors = commonContentErrors(text);
  let hasRequiredStructure = false;

  if (file === 'product/product-brief.zh-CN.md') {
    for (const label of productBriefRequiredLabels) {
      if (!hasFilledValueAfterLabel(text, label)) {
        errors.push(`missing valid content for "${label}"`);
      }
    }
  }

  if (file === 'product/scope-gate.zh-CN.md') {
    hasRequiredStructure = true;
    for (const section of scopeRequiredSections) {
      if (countValidBullets(getSectionByHeading(text, section)) === 0) {
        errors.push(`section "${section}" needs at least one valid bullet`);
        hasRequiredStructure = false;
      }
    }
  }

  if (file === 'product/screen-states.zh-CN.md') {
    hasRequiredStructure = hasValidScreenStateTable(text);
    if (!hasRequiredStructure) errors.push('needs at least one valid page state row');
  }

  if (file === 'product/data-safety.zh-CN.md') {
    hasRequiredStructure = hasValidDataSafetyContent(text);
    if (!hasRequiredStructure) errors.push('needs a clear statement about what the first version keeps');
  }

  if (!hasEnoughUsableContent(text) && !hasRequiredStructure) {
    errors.push('not enough usable content');
  }

  return unique(errors);
}

export function isCompletionProofFilled(text) {
  if (commonContentErrors(text).length > 0) return false;
  return hasEnoughUsableContent(text);
}

function commonContentErrors(text) {
  const errors = [];
  const usable = usableLines(text);

  if (usable.length === 0) {
    errors.push('no meaningful content');
    return errors;
  }

  const placeholder = usable.find((line) => containsPlaceholder(line));
  if (placeholder) errors.push(`contains placeholder "${placeholder.trim()}"`);

  const lowQuality = usable.find((line) => isLowQualityLine(line));
  if (lowQuality) errors.push(`contains low-quality content "${lowQuality.trim()}"`);

  const emptyField = usable.find((line) => hasEmptyField(line));
  if (emptyField) errors.push(`has empty field "${emptyField.trim()}"`);

  if (usable.some((line) => isEmptyBullet(line))) errors.push('has empty bullet');
  if (usable.some((line) => hasEmptyTableCells(line))) errors.push('has empty table row');

  return errors;
}

function containsPlaceholder(text) {
  const lower = text.toLowerCase();
  if (text.includes('--') && !isTableSeparator(text)) return true;
  return placeholderTerms.some((term) => lower.includes(term.toLowerCase()));
}

function isLowQualityLine(line) {
  return lowQualityLines.has(normalizeLine(line));
}

function hasEmptyField(line) {
  const trimmed = stripBulletMarker(line.trim());
  if (trimmed.startsWith('|')) return false;
  return /^[^:：]+[:：]\s*$/.test(trimmed);
}

function isEmptyBullet(line) {
  return /^[-*]\s*$/.test(line.trim());
}

function hasEmptyTableCells(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('|') || isTableSeparator(trimmed)) return false;
  return tableCells(trimmed).filter((cell) => cell.length === 0).length >= 2;
}

function hasFilledValueAfterLabel(text, label) {
  const line = text.split(/\r?\n/).find((item) => {
    const trimmed = stripBulletMarker(item.trim());
    return trimmed.startsWith(`${label}：`) || trimmed.startsWith(`${label}:`);
  });
  if (!line) return false;

  const value = stripBulletMarker(line.trim()).replace(new RegExp(`^${escapeRegExp(label)}[:：]\\s*`), '');
  return isValidTextValue(value, { minCjk: 6, minEnglish: 3 });
}

function getSectionByHeading(text, heading) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === `## ${heading}`);
  if (start === -1) return [];

  const section = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim().startsWith('## ')) break;
    section.push(line);
  }
  return section;
}

function countValidBullets(lines) {
  return lines.filter((line) => {
    const trimmed = line.trim();
    if (!/^[-*]\s+/.test(trimmed)) return false;
    return isValidTextValue(stripBulletMarker(trimmed), { minCjk: 6, minEnglish: 3 });
  }).length;
}

function hasValidScreenStateTable(text) {
  const rows = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('|') && !isTableSeparator(line))
    .map((line) => tableCells(line));

  const headerIndex = rows.findIndex((cells) => screenRequiredColumns.every((column) => cells.includes(column)));
  if (headerIndex === -1) return false;

  const header = rows[headerIndex];
  const indexes = Object.fromEntries(screenRequiredColumns.map((column) => [column, header.indexOf(column)]));
  const dataRows = rows.slice(headerIndex + 1);

  return dataRows.some((row) => {
    if (screenRequiredColumns.some((column) => !row[indexes[column]])) return false;
    return screenRequiredColumns.every((column) => {
      const value = row[indexes[column]];
      if (column === '权限拒绝' && value === '不涉及') return true;
      if (column === '页面') return isValidTextValue(value, { minCjk: 2, minEnglish: 1 });
      return isValidTextValue(value, { minCjk: 4, minEnglish: 2 });
    });
  });
}

function hasValidDataSafetyContent(text) {
  return usableLines(text).some((line) => {
    return /不收集|收集|保存|留在|不记住/.test(line)
      && isValidTextValue(line, { minCjk: 6, minEnglish: 3 });
  });
}

function hasEnoughUsableContent(text) {
  const content = usableLines(text).join('\n');
  const cjkCount = (content.match(/[\u4e00-\u9fff]/g) || []).length;
  const englishWordCount = (content.match(/[A-Za-z]+/g) || []).length;
  return cjkCount >= 30 || englishWordCount >= 15;
}

function usableLines(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .filter((line) => !line.startsWith('#'))
    .filter((line) => !isTableSeparator(line));
}

function isValidTextValue(value, options = {}) {
  const text = value.trim();
  if (!text) return false;
  if (containsPlaceholder(text)) return false;
  if (isLowQualityLine(text)) return false;
  const minCjk = options.minCjk || 1;
  const minEnglish = options.minEnglish || 1;
  const cjkCount = (text.match(/[\u4e00-\u9fff]/g) || []).length;
  const englishWordCount = (text.match(/[A-Za-z]+/g) || []).length;
  return cjkCount >= minCjk || englishWordCount >= minEnglish;
}

function stripBulletMarker(line) {
  return line.replace(/^[-*]\s*/, '');
}

function tableCells(line) {
  return line
    .split('|')
    .slice(1, -1)
    .map((cell) => cell.trim());
}

function isTableSeparator(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('|')) return false;
  return tableCells(trimmed).every((cell) => /^:?-{3,}:?$/.test(cell));
}

function normalizeLine(line) {
  return stripBulletMarker(line.trim())
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[，,；;：:！!？?]/g, '')
    .replace(/[。.]$/g, '。');
}

function unique(items) {
  return [...new Set(items)];
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
