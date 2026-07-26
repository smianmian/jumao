#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { benchmarkCases } from './cases.js';

const repoRoot = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const resultsRoot = path.join(repoRoot, 'benchmark', 'results');
const versions = [
  { id: 'v0.3.1', ref: 'v0.3.1' },
  { id: 'v0.4', ref: 'current' }
];

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n${result.stderr || result.stdout}`);
  }
  return result;
}

function writeJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value, 'utf8');
}

function materializeCase(root, benchmarkCase) {
  for (const [relativePath, content] of Object.entries(benchmarkCase.files)) {
    const output = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, content, 'utf8');
  }
}

function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function textKey(value) {
  return String(value || '').toLowerCase().replace(/[\s\p{P}\p{S}]+/gu, '');
}

function agentOutputs(workspace, manifest) {
  return manifest.agents.map((agent) => ({
    ...readJSON(path.join(workspace, '.jumao', 'runs', manifest.runId, agent.output)),
    manifestAgent: agent
  }));
}

function baselinePriorityTasks(agents) {
  return agents
    .filter((agent) => agent.status === 'completed')
    .flatMap((agent) => (agent.tasks || []).map((task, index) => ({
      taskId: `baseline-${agent.agentId}-${index + 1}`,
      task,
      priority: 'unranked',
      contributingRoles: [agent.agentId],
      evidence: agent.evidence || [],
      findings: agent.findings || [],
      triggerReasons: [],
      triggerReason: null,
      protectedConstraint: null,
      decisionImpact: [],
      source: 'derived-from-v0.3.1-agent-task'
    })));
}

function taskSpecificEvidence(task) {
  if (task.independentFinding) return true;
  return (task.evidence || []).some((item) => String(item.source || '').startsWith('derived:') || String(item.source || '').startsWith('file:'));
}

function explainChain(tasks, version) {
  return tasks.map((task) => ({
    taskId: task.taskId,
    task: task.task,
    contributingRoles: task.contributingRoles || [],
    evidence: task.evidence || [],
    findings: task.findings || [],
    protectedConstraint: task.protectedConstraint || null,
    decisionImpact: task.decisionImpact || [],
    traceable: taskSpecificEvidence(task),
    note: version === 'v0.3.1'
      ? '兼容快照：v0.3.1 未提供原生 priorityTasks 或 decision impact。'
      : '原生 v0.4 priorityTask explain chain。'
  }));
}

function metrics(tasks, taskPlan) {
  const keys = tasks.map((task) => textKey(task.task));
  const uniqueKeys = new Set(keys);
  const taskCount = tasks.length;
  const traceable = tasks.filter(taskSpecificEvidence).length;
  const impact = tasks.filter((task) => (task.decisionImpact || []).length > 0).length;
  return {
    taskCount,
    duplicateTaskCount: taskCount - uniqueKeys.size,
    unsupportedTaskCount: taskCount - traceable,
    evidenceCoverage: taskCount ? traceable / taskCount : 0,
    decisionImpactCoverage: taskCount ? impact / taskCount : 0,
    protectedConstraintCount: new Set((taskPlan.protections || []).map(textKey)).size
  };
}

function percentage(value) {
  return `${Math.round(value * 100)}%`;
}

function delta(current, baseline) {
  const value = current - baseline;
  return value === 0 ? '0' : `${value > 0 ? '+' : ''}${value}`;
}

function suggestions(benchmarkCase, baseline, current) {
  const items = [benchmarkCase.manualReview];
  if (current.taskCount < baseline.taskCount) {
    items.push(`优先交给 Codex 执行 v0.4 的 ${current.taskCount} 项优先任务；baseline 有 ${baseline.taskCount} 项候选任务需要人工筛选。`);
  }
  if (current.unsupportedTaskCount > 0) {
    items.push(`v0.4 仍有 ${current.unsupportedTaskCount} 项缺少任务级可追溯证据，开始编码前应删除或补证。`);
  }
  if (current.decisionImpactCoverage < 1) {
    items.push('开始编码前，人工补齐没有 decision impact 的任务理由。');
  }
  return items;
}

function renderReport(results) {
  const header = [
    '# v0.4 Product Validation Comparison',
    '',
    '基线使用不可变的 `v0.3.1` Git tag；current 使用当前工作区。每次运行都保存原始 manifest、标准化 priorityTasks 和 explain chain。',
    '',
    '说明：v0.3.1 不含原生 `priorityTasks`、独立发现或 decision impact。为公平保留其工作量信号，报告从已完成 Agent 的 `tasks` 生成兼容 priorityTasks；缺少的契约字段不会被补造。',
    '',
    '“evidence coverage”表示任务有任务级直接信号、文件证据或独立发现；“unsupported task”是其反面。',
    ''
  ];
  const rows = [
    '| Case | Version | Tasks | Duplicates | Unsupported | Evidence | Decision impact | Protected constraints |',
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |'
  ];
  for (const result of results) {
    for (const version of versions) {
      const value = result.metrics[version.id];
      rows.push(`| ${result.title} | ${version.id} | ${value.taskCount} | ${value.duplicateTaskCount} | ${value.unsupportedTaskCount} | ${percentage(value.evidenceCoverage)} | ${percentage(value.decisionImpactCoverage)} | ${value.protectedConstraintCount} |`);
    }
  }
  const detail = results.flatMap((result) => [
    `## ${result.title}（${result.category}）`,
    '',
    `- 任务数变化：${result.metrics['v0.3.1'].taskCount} → ${result.metrics['v0.4'].taskCount}（${delta(result.metrics['v0.4'].taskCount, result.metrics['v0.3.1'].taskCount)}）`,
    `- duplicate task 数变化：${result.metrics['v0.3.1'].duplicateTaskCount} → ${result.metrics['v0.4'].duplicateTaskCount}（${delta(result.metrics['v0.4'].duplicateTaskCount, result.metrics['v0.3.1'].duplicateTaskCount)}）`,
    `- unsupported task 数变化：${result.metrics['v0.3.1'].unsupportedTaskCount} → ${result.metrics['v0.4'].unsupportedTaskCount}（${delta(result.metrics['v0.4'].unsupportedTaskCount, result.metrics['v0.3.1'].unsupportedTaskCount)}）`,
    `- evidence coverage：${percentage(result.metrics['v0.3.1'].evidenceCoverage)} → ${percentage(result.metrics['v0.4'].evidenceCoverage)}`,
    `- decision impact coverage：${percentage(result.metrics['v0.3.1'].decisionImpactCoverage)} → ${percentage(result.metrics['v0.4'].decisionImpactCoverage)}`,
    `- protected constraint 数量：${result.metrics['v0.3.1'].protectedConstraintCount} → ${result.metrics['v0.4'].protectedConstraintCount}`,
    '- 人工修改建议：',
    ...result.suggestions.map((item) => `  - ${item}`),
    ''
  ]);
  const baselineTotals = totalMetrics(results, 'v0.3.1');
  const currentTotals = totalMetrics(results, 'v0.4');
  const proven = currentTotals.taskCount < baselineTotals.taskCount
    && currentTotals.unsupportedTaskCount <= baselineTotals.unsupportedTaskCount
    && currentTotals.evidenceCoverage >= baselineTotals.evidenceCoverage
    && currentTotals.decisionImpactCoverage === 1;
  return [
    ...header,
    ...rows,
    '',
    `合计：任务 ${baselineTotals.taskCount} → ${currentTotals.taskCount}；unsupported ${baselineTotals.unsupportedTaskCount} → ${currentTotals.unsupportedTaskCount}；evidence ${percentage(baselineTotals.evidenceCoverage)} → ${percentage(currentTotals.evidenceCoverage)}；decision impact ${percentage(baselineTotals.decisionImpactCoverage)} → ${percentage(currentTotals.decisionImpactCoverage)}。`,
    '',
    ...detail,
    '## 结论',
    '',
    proven
      ? '是。四个案例显示 v0.4 产生了更少的候选任务，未增加不受支持的任务，并为每个优先任务保存了可追溯的 evidence、finding 与 decision impact。它适合交给 Codex 执行，但报告中的人工复核项仍需在编码前确认。'
      : '否。当前指标尚不足以证明“更少但更准确的任务，并且每个任务都有可追溯理由”；请先检查报告中的人工修改建议。',
    ''
  ].join('\n');
}

function totalMetrics(results, version) {
  const totals = results.reduce((sum, result) => {
    const value = result.metrics[version];
    sum.taskCount += value.taskCount;
    sum.duplicateTaskCount += value.duplicateTaskCount;
    sum.unsupportedTaskCount += value.unsupportedTaskCount;
    sum.traceableTasks += Math.round(value.evidenceCoverage * value.taskCount);
    sum.impactTasks += Math.round(value.decisionImpactCoverage * value.taskCount);
    return sum;
  }, { taskCount: 0, duplicateTaskCount: 0, unsupportedTaskCount: 0, traceableTasks: 0, impactTasks: 0 });
  return {
    ...totals,
    evidenceCoverage: totals.taskCount ? totals.traceableTasks / totals.taskCount : 0,
    decisionImpactCoverage: totals.taskCount ? totals.impactTasks / totals.taskCount : 0
  };
}

function runVersion(version, sourceRoot, tempRoot, benchmarkCase) {
  const workspace = path.join(tempRoot, version.id, benchmarkCase.id);
  materializeCase(workspace, benchmarkCase);
  run(process.execPath, [path.join(sourceRoot, 'bin', 'jumao.js'), 'plan', workspace, '--force'], sourceRoot);
  const latest = readJSON(path.join(workspace, '.jumao', 'latest-run.json'));
  const runRoot = path.join(workspace, latest.runPath);
  const manifest = readJSON(path.join(runRoot, 'manifest.json'));
  const taskPlan = readJSON(path.join(runRoot, 'task-plan.json'));
  const agents = agentOutputs(workspace, manifest);
  const priorityTasks = version.id === 'v0.3.1'
    ? baselinePriorityTasks(agents)
    : taskPlan.priorityTasks || [];
  return { manifest, taskPlan, priorityTasks, explainChain: explainChain(priorityTasks, version.id) };
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-benchmark-'));
  const baselineRoot = path.join(tempRoot, 'v0.3.1-source');
  try {
    run('git', ['worktree', 'add', '--detach', baselineRoot, 'v0.3.1'], repoRoot);
    for (const benchmarkCase of benchmarkCases) {
      fs.rmSync(path.join(resultsRoot, benchmarkCase.id), { recursive: true, force: true });
    }
    fs.rmSync(path.join(resultsRoot, 'comparison-report.md'), { force: true });
    const results = benchmarkCases.map((benchmarkCase) => {
      const snapshots = {
        'v0.3.1': runVersion(versions[0], baselineRoot, tempRoot, benchmarkCase),
        'v0.4': runVersion(versions[1], repoRoot, tempRoot, benchmarkCase)
      };
      const caseRoot = path.join(resultsRoot, benchmarkCase.id);
      for (const [version, snapshot] of Object.entries(snapshots)) {
        const versionRoot = path.join(caseRoot, version);
        writeJSON(path.join(versionRoot, 'manifest.json'), snapshot.manifest);
        writeJSON(path.join(versionRoot, 'priority-tasks.json'), snapshot.priorityTasks);
        writeJSON(path.join(versionRoot, 'explain-chain.json'), snapshot.explainChain);
      }
      const result = {
        ...benchmarkCase,
        metrics: {
          'v0.3.1': metrics(snapshots['v0.3.1'].priorityTasks, snapshots['v0.3.1'].taskPlan),
          'v0.4': metrics(snapshots['v0.4'].priorityTasks, snapshots['v0.4'].taskPlan)
        }
      };
      result.suggestions = suggestions(benchmarkCase, result.metrics['v0.3.1'], result.metrics['v0.4']);
      return result;
    });
    const report = renderReport(results);
    writeText(path.join(resultsRoot, 'comparison-report.md'), report);
    process.stdout.write(`Wrote ${path.relative(repoRoot, path.join(resultsRoot, 'comparison-report.md'))}\n`);
  } finally {
    if (fs.existsSync(baselineRoot)) run('git', ['worktree', 'remove', '--force', baselineRoot], repoRoot);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

main();
