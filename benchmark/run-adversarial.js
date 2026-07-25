#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { adversarialCases } from './adversarial-cases.js';

const repoRoot = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const resultsRoot = path.join(repoRoot, 'benchmark', 'results', 'adversarial');

function command(binary, args, cwd) {
  const result = spawnSync(binary, args, { cwd, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`${binary} ${args.join(' ')}\n${result.stderr || result.stdout}`);
}

function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function read(file) { return JSON.parse(fs.readFileSync(file, 'utf8')); }

function materialize(root, benchmarkCase) {
  for (const [relative, content] of Object.entries(benchmarkCase.files)) write(path.join(root, relative), content);
}

function execute(label, sourceRoot, tempRoot, benchmarkCase) {
  const workspace = path.join(tempRoot, label, benchmarkCase.id);
  materialize(workspace, benchmarkCase);
  command(process.execPath, [path.join(sourceRoot, 'bin', 'jumao.js'), 'plan', workspace, '--force'], sourceRoot);
  const latest = read(path.join(workspace, '.jumao', 'latest-run.json'));
  const runRoot = path.join(workspace, latest.runPath);
  const manifest = read(path.join(runRoot, 'manifest.json'));
  const agentOutputs = manifest.agents.map((agent) => read(path.join(runRoot, agent.output)));
  const nativePriorityTasks = read(path.join(runRoot, 'task-plan.json')).priorityTasks || [];
  const priorityTasks = nativePriorityTasks.length > 0
    ? nativePriorityTasks
    : agentOutputs.filter((agent) => agent.status === 'completed').flatMap((agent) => (agent.tasks || []).map((task) => ({
      task,
      contributingRoles: [agent.agentId],
      decisionImpact: []
    })));
  return { manifest, priorityTasks, agentOutputs };
}

function observed(snapshot) {
  return {
    priorityTaskCount: snapshot.priorityTasks.length,
    blockingQuestions: snapshot.manifest.blockingQuestions,
    completedAgents: snapshot.agentOutputs.filter((agent) => agent.status === 'completed').map((agent) => agent.agentId),
    tasks: snapshot.priorityTasks.map((task) => ({ task: task.task, roles: task.contributingRoles, impact: task.decisionImpact }))
  };
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-adversarial-'));
  const baselineRoot = path.join(tempRoot, 'v0.3.1-source');
  try {
    command('git', ['worktree', 'add', '--detach', baselineRoot, 'v0.3.1'], repoRoot);
    fs.rmSync(resultsRoot, { recursive: true, force: true });
    const summary = [];
    for (const benchmarkCase of adversarialCases) {
      const root = path.join(resultsRoot, benchmarkCase.id);
      write(path.join(root, 'expected.md'), `# ${benchmarkCase.title}\n\n## 运行前人工期望\n\n${benchmarkCase.expected}\n`);
      const baseline = execute('v0.3.1', baselineRoot, tempRoot, benchmarkCase);
      const current = execute('v0.4', repoRoot, tempRoot, benchmarkCase);
      write(path.join(root, 'v0.3.1.json'), observed(baseline));
      write(path.join(root, 'v0.4.json'), observed(current));
      summary.push({ id: benchmarkCase.id, title: benchmarkCase.title, expected: benchmarkCase.expected, baseline: observed(baseline), current: observed(current) });
    }
    write(path.join(resultsRoot, 'comparison.json'), summary);
    write(path.join(resultsRoot, 'comparison.md'), [
      '# 对抗性案例版本对比', '',
      '每个期望在运行前已保存到对应 `expected.md`；本报告只记录观察结果，不根据结果修改期望或评分。', '',
      ...summary.flatMap((item) => [
        `## ${item.title}`, '', `- 预期：${item.expected}`,
        `- v0.3.1：${item.baseline.priorityTaskCount} 项任务；blocked：${item.baseline.blockingQuestions.length}。`,
        `- v0.4：${item.current.priorityTaskCount} 项 priorityTasks；blocked：${item.current.blockingQuestions.length}；completed：${item.current.completedAgents.join('、') || '无'}。`, ''
      ])
    ].join('\n'));
    process.stdout.write(`Wrote ${path.relative(repoRoot, resultsRoot)}\n`);
  } finally {
    if (fs.existsSync(baselineRoot)) command('git', ['worktree', 'remove', '--force', baselineRoot], repoRoot);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

main();
