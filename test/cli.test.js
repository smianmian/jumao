import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const repoRoot = path.resolve(new URL('..', import.meta.url).pathname);
const cli = path.join(repoRoot, 'bin', 'jumao.js');

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-test-'));
}

function createProductWorkspace(name = 'AI Note') {
  const workspace = path.join(tempDir(), 'workspace');
  const created = spawnSync(process.execPath, [cli, 'new', name, '--dir', workspace], { encoding: 'utf8' });
  assert.equal(created.status, 0, created.stderr);
  return workspace;
}

function writeWorkspaceFiles(workspace, files) {
  for (const [file, text] of Object.entries(files)) {
    fs.writeFileSync(path.join(workspace, file), text, 'utf8');
  }
}

function writeMinimalValidCore(workspace) {
  writeWorkspaceFiles(workspace, {
    'product/product-brief.zh-CN.md': `# 产品简报

主要用户：第一次做小工具但不会写代码的独立开发者。
第一版先证明一件事：用户能在写代码前把产品目标和首版范围讲清楚。
用户能完成：创建项目工作区、填写产品边界、生成给 AI 编程工具的任务包。
我们能看到的证据：生成的任务包能被 Codex 读取，并且不会要求 AI 自己猜产品范围。
不能承诺：不能承诺一键生成完整 App。
不能收集：首版不收集用户账号、手机号、支付信息、隐私数据。
会影响真实用户或钱的动作：发布 npm、push 远程仓库、删除文件、调用付费 API 都必须人工确认。
`,
    'product/scope-gate.zh-CN.md': `# 范围门禁

## 首版必须做
- 创建本地产品工作区。
- 检查核心产品文件是否填写。
- 打包给 AI 编程工具读取的任务上下文。

## 首版明确不做
- 不调用任何模型 API。
- 不自动发布 npm。
- 不自动 push 远程仓库。

## 不要让 AI 自己加
- 不要自行新增 Web UI。
- 不要自行新增登录系统。
- 不要自行新增云服务。

## 需要人工确认的动作
- 发布 npm 前必须人工确认。
- push 远程仓库前必须人工确认。
- 删除用户文件前必须人工确认。
`,
    'product/screen-states.zh-CN.md': `# 页面状态

| 页面 | 用户想做什么 | 加载中 | 空状态 | 错误状态 | 成功状态 | 权限拒绝 |
|---|---|---|---|---|---|---|
| CLI 新建项目 | 创建一个产品工作区 | 显示正在生成文件 | 提示当前目录为空可继续创建 | 提示目录不可写或文件冲突 | 显示生成路径和下一步命令 | 不涉及 |
`,
    'product/data-safety.zh-CN.md': `# 数据安全

首版不收集用户数据。
首版不使用第三方服务。
不收集手机号、身份证、定位、通讯录、支付信息。
用户可以删除本地工作区文件，Jumao 不保留云端数据。
删除后无保留数据。
`
  });
}

function writeFilledCompletionProof(workspace) {
  writeWorkspaceFiles(workspace, {
    'proof/release-proof.zh-CN.md': `# 完成证据

## 本轮改了什么
- 实现严格门禁输出。

## 没有改什么
- 没有发布远程仓库。

## 验证证据
| 证据 | 文件或命令 | 结果 |
|---|---|---|
| 命令验证 | \`npm run check\` | 通过 |

## 还不能说完成的事
- 不能说已经发布 npm。

## 下一步
- 等人工验收后再提交。
`
  });
}

function minimalAnswers(overrides = {}) {
  return {
    primaryUser: '第一次做小工具但不会写代码的独立开发者',
    firstVersionGoal: '用户能在写代码前把产品目标和首版范围讲清楚',
    userCanDo: '创建项目工作区、填写产品边界、生成给 AI 编程工具的任务包',
    successEvidence: '生成的任务包能被 Codex 读取，并且不会要求 AI 自己猜产品范围',
    cannotPromise: '不能承诺一键生成完整 App',
    cannotCollect: '首版不收集用户账号、手机号、支付信息、隐私数据',
    humanConfirmActions: [
      '发布 npm 前必须人工确认',
      'push 远程仓库前必须人工确认',
      '删除用户文件前必须人工确认'
    ],
    mustDo: [
      '创建本地产品工作区',
      '检查核心产品文件是否填写',
      '打包给 AI 编程工具读取的任务上下文'
    ],
    wontDo: [
      '不调用任何模型 API',
      '不自动发布 npm',
      '不自动 push 远程仓库'
    ],
    aiMustNotAdd: [
      '不要自行新增 Web UI',
      '不要自行新增登录系统',
      '不要自行新增云服务'
    ],
    mainScreen: {
      name: 'CLI 新建项目',
      userGoal: '创建一个产品工作区',
      loading: '显示正在生成文件',
      empty: '提示当前目录为空可继续创建',
      error: '提示目录不可写或文件冲突',
      success: '显示生成路径和下一步命令',
      permissionDenied: '不涉及'
    },
    dataSafety: {
      collects: '首版不收集用户数据',
      doesNotCollect: '不收集手机号、身份证、定位、通讯录、支付信息',
      thirdParties: '首版不使用第三方服务',
      deletion: '用户可以删除本地工作区文件，Jumao 不保留云端数据',
      retention: '删除后无保留数据'
    },
    ...overrides
  };
}

function writeAnswersFile(answers = minimalAnswers()) {
  const answersPath = path.join(tempDir(), 'answers.json');
  fs.writeFileSync(answersPath, JSON.stringify(answers, null, 2), 'utf8');
  return answersPath;
}

function doctorAnswers(overrides = {}) {
  return {
    projectStage: 'prototype',
    launchIntent: 'public_launch',
    storePlan: 'app_store',
    ownerType: 'company',
    loginNeeded: true,
    chargingPlan: 'subscription',
    crossDeviceData: 'needed',
    sensitiveData: ['health'],
    chinaUsers: true,
    supportNeeds: ['refund', 'deletion', 'account'],
    ...overrides
  };
}

function writeDoctorAnswersFile(answers = doctorAnswers()) {
  const answersPath = path.join(tempDir(), 'doctor-answers.json');
  fs.writeFileSync(answersPath, JSON.stringify(answers, null, 2), 'utf8');
  return answersPath;
}

function writeCodexAgentGates(workspace) {
  const governanceDir = path.join(workspace, 'governance');
  fs.mkdirSync(governanceDir, { recursive: true });
  fs.writeFileSync(
    path.join(governanceDir, 'codex-agent-gates.md'),
    `# Codex Agent Gates

- 没有 DATA_GOVERNANCE_REGISTER.md，不得新增数据库字段。
- 没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。
- 没有 HEALTH_CLAIMS_APPROVAL_LOG.md，不得新增健康结论、推送文案、报告文案。
- 没有 IAP_REVENUE_OPS_CHECKLIST.md，不得接入 StoreKit 生产订阅。
- 没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。
- 没有 CLOUD_IAM_SECRETS_BACKUP_SPEC.md，不得部署生产环境。
- 没有 SUPPORT_REFUND_DELETION_PLAYBOOK.md，不得上线带登录和订阅的版本。
`,
    'utf8'
  );
}

function readStatusJson(workspace) {
  return JSON.parse(fs.readFileSync(path.join(workspace, '.jumao', 'status.json'), 'utf8'));
}

function outputLineCount(text) {
  return text.trimEnd().split('\n').length;
}

function createInterviewedWorkspace() {
  const workspace = createProductWorkspace();
  const answersPath = writeAnswersFile();
  const interviewed = spawnSync(process.execPath, [cli, 'interview', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });
  assert.equal(interviewed.status, 0, interviewed.stdout + interviewed.stderr);
  return workspace;
}

test('prints help', () => {
  const result = spawnSync(process.execPath, [cli, '--help'], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /jumao init/);
});

test('creates and checks a product workspace', () => {
  const dir = tempDir();
  const workspace = path.join(dir, 'my-product');

  const created = spawnSync(process.execPath, [cli, 'new', '我的产品', '--dir', workspace], { encoding: 'utf8' });
  assert.equal(created.status, 0, created.stderr);
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'product-brief.zh-CN.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'AGENTS.md')));

  const checked = spawnSync(process.execPath, [cli, 'check', workspace], { encoding: 'utf8' });
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
});

test('status shows sleeping when no cat status exists', () => {
  const workspace = createProductWorkspace('Cat Status');

  const result = spawnSync(process.execPath, [cli, 'status', workspace], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /橘猫状态：还没检查（sleeping）/);
  assert.match(result.stdout, /不是项目没问题，也不是项目失败|先运行 jumao doctor/);
  assert.ok(outputLineCount(result.stdout) <= 12);
  assert.ok(!fs.existsSync(path.join(workspace, '.jumao', 'status.json')));
});

test('status exits for a directory that is not a Jumao workspace', () => {
  const workspace = tempDir();

  const result = spawnSync(process.execPath, [cli, 'status', workspace], { encoding: 'utf8' });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /请先运行 jumao new/);
});

test('default check does not inspect template content', () => {
  const workspace = createProductWorkspace();

  const checked = spawnSync(process.execPath, [cli, 'check', workspace], { encoding: 'utf8' });
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.match(checked.stdout, /Jumao check passed/);
});

test('strict check fails for a new workspace', () => {
  const workspace = createProductWorkspace();

  const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });
  assert.equal(checked.status, 1);
  assert.match(checked.stdout, /Jumao strict check found gaps/);
  assert.match(checked.stdout, /Errors:/);
  assert.match(checked.stdout, /product\/product-brief\.zh-CN\.md/);
  assert.match(checked.stdout, /product\/screen-states\.zh-CN\.md/);
});

test('strict check supports flag before dir and shorthand forms', () => {
  const workspace = createProductWorkspace();

  const forms = [
    ['check', workspace, '--strict'],
    ['check', '--strict', workspace],
    ['check', workspace, '-s'],
    ['check', '-s', workspace]
  ];

  for (const args of forms) {
    const checked = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    assert.equal(checked.status, 1, `${args.join(' ')} should fail strict check`);
    assert.match(checked.stdout, /Jumao strict check found gaps/);
  }
});

test('strict check rejects placeholder terms', () => {
  const terms = ['TODO', 'TBD', '待填写', 'placeholder'];

  for (const term of terms) {
    const workspace = createProductWorkspace();
    writeMinimalValidCore(workspace);
    writeFilledCompletionProof(workspace);
    fs.appendFileSync(path.join(workspace, 'product', 'product-brief.zh-CN.md'), `\n${term}\n`, 'utf8');

    const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });
    assert.equal(checked.status, 1, `${term} should fail strict check`);
    assert.match(checked.stdout, new RegExp(term, 'i'));
  }
});

test('strict check rejects low-quality filler', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);
  writeFilledCompletionProof(workspace);
  const briefPath = path.join(workspace, 'product', 'product-brief.zh-CN.md');
  fs.writeFileSync(briefPath, '# 产品简报\n\n已填写。\n', 'utf8');

  const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });
  assert.equal(checked.status, 1);
  assert.match(checked.stdout, /已填写/);
});

test('strict check rejects empty structures', () => {
  const cases = [
    {
      file: 'product/product-brief.zh-CN.md',
      text: '# 产品简报\n\n主要用户：\n',
      pattern: /empty field|主要用户/
    },
    {
      file: 'product/scope-gate.zh-CN.md',
      text: '# 范围门禁\n\n## 首版必须做\n-\n',
      pattern: /empty bullet/
    },
    {
      file: 'product/screen-states.zh-CN.md',
      text: '# 页面状态\n\n| 页面 | 用户想做什么 | 加载中 | 空状态 | 错误状态 | 成功状态 | 权限拒绝 |\n|---|---|---|---|---|---|---|\n| 首页 |  |  |  |  |  |  |\n',
      pattern: /empty table row/
    },
    {
      file: 'product/screen-states.zh-CN.md',
      text: '# 页面状态\n\n| 页面 | 用户想做什么 | 加载中 | 空状态 | 错误状态 | 成功状态 | 权限拒绝 |\n|---|---|---|---|---|---|---|\n| 首页 | 使用 | 已填写 | 已填写 | 已填写 | 已填写 | 无 |\n',
      pattern: /已填写|needs at least one valid page state row/
    }
  ];

  for (const item of cases) {
    const workspace = createProductWorkspace();
    writeMinimalValidCore(workspace);
    writeFilledCompletionProof(workspace);
    fs.writeFileSync(path.join(workspace, item.file), item.text, 'utf8');

    const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });
    assert.equal(checked.status, 1, `${item.file} should fail strict check`);
    assert.match(checked.stdout, item.pattern);
  }
});

test('strict check warns for empty completion proof without failing', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);

  const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.match(checked.stdout, /Jumao strict check passed/);
  assert.match(checked.stdout, /Warnings:/);
  assert.match(checked.stdout, /completion proof is not filled yet/);
});

test('strict check passes for minimal valid Chinese content', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);
  writeFilledCompletionProof(workspace);

  const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });

  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.match(checked.stdout, /Jumao strict check passed/);
  assert.doesNotMatch(checked.stdout, /Warnings:/);
});

test('audit reports gaps for a new workspace', () => {
  const workspace = createProductWorkspace();

  const audited = spawnSync(process.execPath, [cli, 'audit', workspace], { encoding: 'utf8' });

  assert.equal(audited.status, 0, audited.stdout + audited.stderr);
  assert.match(audited.stdout, /Jumao audit report/);
  assert.match(audited.stdout, /Workspace status: not ready/);
  assert.match(audited.stdout, /Next safe task for AI/);
});

test('audit write creates a report file', () => {
  const workspace = createProductWorkspace();

  const audited = spawnSync(process.execPath, [cli, 'audit', workspace, '--write'], { encoding: 'utf8' });
  const reportPath = path.join(workspace, 'tasks', 'audit-report.md');

  assert.equal(audited.status, 0, audited.stdout + audited.stderr);
  assert.ok(fs.existsSync(reportPath));
  assert.match(fs.readFileSync(reportPath, 'utf8'), /Findings/);
});

test('audit rejects an empty directory', () => {
  const workspace = tempDir();

  const audited = spawnSync(process.execPath, [cli, 'audit', workspace], { encoding: 'utf8' });

  assert.equal(audited.status, 1);
  assert.match(audited.stderr, /not a valid Jumao workspace/);
});

test('audit reports planning-ready workspace with empty completion proof warning', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);

  const audited = spawnSync(process.execPath, [cli, 'audit', workspace], { encoding: 'utf8' });

  assert.equal(audited.status, 0, audited.stdout + audited.stderr);
  assert.match(audited.stdout, /Workspace status: planning ready, not release ready/);
  assert.doesNotMatch(audited.stdout, /\[error\]/);
  assert.match(audited.stdout, /\[warning\] proof\/release-proof\.zh-CN\.md/);
  assert.match(audited.stdout, /completion proof is not filled yet/);
});

test('interview answers write the four core product files', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeAnswersFile();

  const interviewed = spawnSync(process.execPath, [cli, 'interview', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(interviewed.status, 0, interviewed.stdout + interviewed.stderr);
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'product-brief.zh-CN.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'scope-gate.zh-CN.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'screen-states.zh-CN.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'data-safety.zh-CN.md')));
  assert.match(fs.readFileSync(path.join(workspace, 'product', 'product-brief.zh-CN.md'), 'utf8'), /第一次做小工具/);
});

test('interview output passes strict check with completion proof warning', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeAnswersFile();

  const interviewed = spawnSync(process.execPath, [cli, 'interview', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });
  const checked = spawnSync(process.execPath, [cli, 'check', workspace, '--strict'], { encoding: 'utf8' });

  assert.equal(interviewed.status, 0, interviewed.stdout + interviewed.stderr);
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.match(checked.stdout, /Jumao strict check passed/);
  assert.match(checked.stdout, /Warnings:/);
  assert.match(checked.stdout, /completion proof is not filled yet/);
});

test('interview refuses to overwrite filled core files without force', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);
  const answersPath = writeAnswersFile();

  const interviewed = spawnSync(process.execPath, [cli, 'interview', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(interviewed.status, 1);
  assert.match(interviewed.stderr, /--force/);
});

test('interview force overwrites filled core files', () => {
  const workspace = createProductWorkspace();
  writeMinimalValidCore(workspace);
  const answersPath = writeAnswersFile(minimalAnswers({ primaryUser: '正在用 AI 落地第一个产品的创作者' }));

  const interviewed = spawnSync(
    process.execPath,
    [cli, 'interview', workspace, '--answers', answersPath, '--force'],
    { encoding: 'utf8' }
  );

  assert.equal(interviewed.status, 0, interviewed.stdout + interviewed.stderr);
  assert.match(fs.readFileSync(path.join(workspace, 'product', 'product-brief.zh-CN.md'), 'utf8'), /正在用 AI/);
});

test('initializes a ready-to-fill workspace', () => {
  const workspace = tempDir();

  const initialized = spawnSync(process.execPath, [cli, 'init', workspace], { encoding: 'utf8' });
  assert.equal(initialized.status, 0, initialized.stderr);
  assert.ok(fs.existsSync(path.join(workspace, 'templates', 'product-brief.zh-CN.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'product', 'product-brief.zh-CN.md')));

  const checked = spawnSync(process.execPath, [cli, 'check', workspace], { encoding: 'utf8' });
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
});

test('packs product context for an AI coding tool', () => {
  const dir = tempDir();
  const workspace = path.join(dir, 'packet');
  spawnSync(process.execPath, [cli, 'new', 'AI Note', '--dir', workspace], { encoding: 'utf8' });

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace], { encoding: 'utf8' });
  assert.equal(packed.status, 0, packed.stderr);

  const taskPack = fs.readFileSync(path.join(workspace, 'jumao-task-pack.md'), 'utf8');
  assert.match(taskPack, /橘猫 AI 任务包/);
  assert.match(taskPack, /product-brief/);
});

test('pack target codex writes a Codex task pack', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'codex'], { encoding: 'utf8' });
  const taskPackPath = path.join(workspace, 'tasks', 'codex-task-pack.md');
  const taskPack = fs.readFileSync(taskPackPath, 'utf8');

  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.match(packed.stdout, /codex-task-pack\.md/);
  assert.match(taskPack, /## Product brief/);
  assert.match(taskPack, /## Scope gate/);
  assert.match(taskPack, /## Screen states/);
  assert.match(taskPack, /## Data safety/);
  assert.match(taskPack, /## Release proof status/);
  assert.match(taskPack, /## AI execution rules/);
  assert.match(taskPack, /## First safe task/);
  assert.match(taskPack, /## Do not do yet/);
  assert.match(taskPack, /Read AGENTS\.md first/);
  assert.doesNotMatch(taskPack, /# Agent Review Board Gates/);
});

test('pack target includes Agent Review Board gates when governance file exists', () => {
  const targets = ['codex', 'claude', 'cursor'];

  for (const target of targets) {
    const workspace = createInterviewedWorkspace();
    writeCodexAgentGates(workspace);

    const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', target], { encoding: 'utf8' });
    const taskPack = fs.readFileSync(path.join(workspace, 'tasks', `${target}-task-pack.md`), 'utf8');

    assert.equal(packed.status, 0, packed.stdout + packed.stderr);
    assert.match(taskPack, /# Agent Review Board Gates/);
    assert.match(taskPack, /# Codex Agent Gates/);
    assert.match(taskPack, /DATA_GOVERNANCE_REGISTER\.md/);
    assert.match(taskPack, /SDK_VENDOR_REGISTER\.md/);
    assert.match(taskPack, /HEALTH_CLAIMS_APPROVAL_LOG\.md/);
    assert.match(taskPack, /IAP_REVENUE_OPS_CHECKLIST\.md/);
    assert.match(taskPack, /RELEASE_MANAGER_CHECKLIST\.md/);
    assert.match(taskPack, /CLOUD_IAM_SECRETS_BACKUP_SPEC\.md/);
    assert.match(taskPack, /SUPPORT_REFUND_DELETION_PLAYBOOK\.md/);
  }
});

test('pack target claude writes a Claude task pack', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'claude'], { encoding: 'utf8' });
  const taskPack = fs.readFileSync(path.join(workspace, 'tasks', 'claude-task-pack.md'), 'utf8');

  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.match(taskPack, /Read CLAUDE\.md first/);
  assert.match(taskPack, /Explain assumptions before large changes/);
});

test('pack target cursor writes a Cursor task pack', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'cursor'], { encoding: 'utf8' });
  const taskPack = fs.readFileSync(path.join(workspace, 'tasks', 'cursor-task-pack.md'), 'utf8');

  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.match(taskPack, /Keep edits small/);
  assert.match(taskPack, /Prefer existing project structure/);
});

test('pack target fails when strict gate has errors', () => {
  const workspace = createProductWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'codex'], { encoding: 'utf8' });
  const status = readStatusJson(workspace);

  assert.equal(packed.status, 1);
  assert.match(packed.stderr, /strict gate failed/);
  assert.match(packed.stderr, /jumao audit/);
  assert.match(packed.stderr, /jumao interview/);
  assert.ok(!fs.existsSync(path.join(workspace, 'tasks', 'codex-task-pack.md')));
  assert.equal(status.cat.state, 'blocked');
  assert.equal(status.lastRun.command, 'pack');
  assert.ok(status.blockers.length > 0);
});

test('pack target passes after interview answers', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'codex'], { encoding: 'utf8' });
  const status = readStatusJson(workspace);

  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.ok(fs.existsSync(path.join(workspace, 'tasks', 'codex-task-pack.md')));
  assert.equal(status.cat.state, 'packed');
  assert.equal(status.artifacts.latestTaskPack, 'tasks/codex-task-pack.md');
  assert.match(status.cat.message, /不是已复制剪贴板/);
});

test('release proof warning does not block target pack', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'codex'], { encoding: 'utf8' });
  const taskPack = fs.readFileSync(path.join(workspace, 'tasks', 'codex-task-pack.md'), 'utf8');
  const status = readStatusJson(workspace);

  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.match(taskPack, /completion proof is not filled yet/);
  assert.equal(status.cat.state, 'packed');
});

test('packed status keeps complete status fields and warns about remaining blockers', () => {
  const workspace = createInterviewedWorkspace();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath, '--write'], {
    encoding: 'utf8'
  });
  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'codex'], { encoding: 'utf8' });
  const status = readStatusJson(workspace);
  const statusOutput = spawnSync(process.execPath, [cli, 'status', workspace], { encoding: 'utf8' });

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  assert.equal(status.cat.state, 'packed');
  assert.ok(!Number.isNaN(Date.parse(status.updatedAt)));
  assert.equal(status.workspace.name, 'AI Note');
  assert.equal(status.workspace.path, path.resolve(workspace));
  assert.equal(status.cat.message, '任务包已生成，但仍需先处理关键门禁。');
  assert.ok(Array.isArray(status.blockers));
  assert.ok(status.blockers.length > 0);
  assert.equal(typeof status.nextSafeTask, 'string');
  assert.equal(status.artifacts.agentReport, 'governance/agent-review-report.md');
  assert.equal(status.artifacts.agentFindings, 'governance/agent-findings.json');
  assert.equal(status.artifacts.codexGates, 'governance/codex-agent-gates.md');
  assert.equal(status.artifacts.latestTaskPack, 'tasks/codex-task-pack.md');
  assert.equal(statusOutput.status, 0, statusOutput.stdout + statusOutput.stderr);
  assert.match(statusOutput.stdout, /任务包已生成，但门禁仍需处理。/);
  assert.ok(outputLineCount(statusOutput.stdout) <= 12);
});

test('pack target rejects an unknown target', () => {
  const workspace = createInterviewedWorkspace();

  const packed = spawnSync(process.execPath, [cli, 'pack', workspace, '--target', 'unknown'], { encoding: 'utf8' });

  assert.equal(packed.status, 1);
  assert.match(packed.stderr, /Unknown pack target/);
});

test('doctor answers output a plain-language diagnosis', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.match(doctored.stdout, /你现在处于什么阶段/);
  assert.match(doctored.stdout, /我帮你补一下认知/);
  assert.match(doctored.stdout, /你可能需要什么/);
  assert.match(doctored.stdout, /现在可以先不做什么/);
  assert.match(doctored.stdout, /下一步最小安全任务/);
  assert.match(doctored.stdout, /触发了哪些 Agent 组/);
  assert.match(doctored.stdout, /触发了哪些关键 Agent/);
  assert.match(doctored.stdout, /给 Codex 的硬门禁/);
  assert.doesNotMatch(doctored.stdout, /要不要后端|要不要数据库|要不要云服务器|要不要 RBAC|要不要 IAP|要不要 SRE|要不要 CI\/CD/i);
});

test('doctor write creates governance files without writing task files', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath, '--write'], {
    encoding: 'utf8'
  });
  const status = readStatusJson(workspace);
  const statusText = JSON.stringify(status);

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.ok(fs.existsSync(path.join(workspace, 'governance', 'agent-review-report.md')));
  assert.ok(fs.existsSync(path.join(workspace, 'governance', 'agent-findings.json')));
  assert.ok(fs.existsSync(path.join(workspace, 'governance', 'codex-agent-gates.md')));
  assert.ok(fs.existsSync(path.join(workspace, '.jumao', 'status.json')));
  assert.ok(!fs.existsSync(path.join(workspace, 'tasks')));
  assert.match(fs.readFileSync(path.join(workspace, 'governance', 'codex-agent-gates.md'), 'utf8'), /DATA_GOVERNANCE_REGISTER\.md/);
  assert.equal(status.cat.state, 'blocked');
  assert.equal(status.lastRun.command, 'doctor');
  assert.equal(status.agentBoard.triggeredAgentCount > 0, true);
  assert.doesNotMatch(statusText, /public_launch|subscription|ready_to_release|doctorAnswers/);
});

test('doctor write stores ready status when only base board advice is active', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile({
    projectStage: 'prototype',
    launchIntent: 'private',
    storePlan: 'none',
    ownerType: 'personal',
    loginNeeded: false,
    chargingPlan: 'free',
    crossDeviceData: 'local_only',
    sensitiveData: [],
    chinaUsers: false,
    supportNeeds: []
  });

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath, '--write'], {
    encoding: 'utf8'
  });
  const status = readStatusJson(workspace);

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.equal(status.cat.state, 'ready');
  assert.match(status.cat.message, /不是可以上线/);
  assert.equal(status.agentBoard.blockedGroupCount, 0);
});

test('doctor status writes idle, triggered, and blocked Agent groups from registry ids', () => {
  const readyWorkspace = createProductWorkspace();
  const readyAnswersPath = writeDoctorAnswersFile({
    projectStage: 'prototype',
    launchIntent: 'private',
    storePlan: 'none',
    ownerType: 'personal',
    loginNeeded: false,
    chargingPlan: 'free',
    crossDeviceData: 'local_only',
    sensitiveData: [],
    chinaUsers: false,
    supportNeeds: []
  });
  const blockedWorkspace = createProductWorkspace();
  const blockedAnswersPath = writeDoctorAnswersFile();

  const readyDoctor = spawnSync(process.execPath, [cli, 'doctor', readyWorkspace, '--answers', readyAnswersPath, '--write'], {
    encoding: 'utf8'
  });
  const blockedDoctor = spawnSync(process.execPath, [cli, 'doctor', blockedWorkspace, '--answers', blockedAnswersPath, '--write'], {
    encoding: 'utf8'
  });
  const readyStatus = readStatusJson(readyWorkspace);
  const blockedStatus = readStatusJson(blockedWorkspace);
  const readyGroups = new Map(readyStatus.agentBoard.groups.map((group) => [group.id, group]));
  const blockedGroups = new Map(blockedStatus.agentBoard.groups.map((group) => [group.id, group]));
  const dataPrivacyBlocker = blockedStatus.blockers.find((blocker) => blocker.groupId === 'data_privacy');

  assert.equal(readyDoctor.status, 0, readyDoctor.stdout + readyDoctor.stderr);
  assert.equal(blockedDoctor.status, 0, blockedDoctor.stdout + blockedDoctor.stderr);
  assert.equal(readyStatus.agentBoard.groups.length, 8);
  assert.deepEqual(readyGroups.get('data_privacy'), {
    id: 'data_privacy',
    name: '数据与隐私 Agent 组',
    state: 'idle',
    triggeredAgentCount: 0,
    message: ''
  });
  assert.equal(readyGroups.get('product_design').state, 'triggered');
  assert.equal(readyGroups.get('product_design').triggeredAgentCount, 3);
  assert.equal(blockedGroups.get('data_privacy').state, 'blocked');
  assert.ok(blockedGroups.get('data_privacy').triggeredAgentCount > 0);
  assert.equal(blockedGroups.get('data_privacy').message, dataPrivacyBlocker.message);
  assert.equal(dataPrivacyBlocker.groupId, 'data_privacy');
});

test('doctor triggers app store, login, subscription, health, and filing agents', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.match(doctored.stdout, /App Store 上架负责人 Agent/);
  assert.match(doctored.stdout, /后端工程师 Agent/);
  assert.match(doctored.stdout, /数据治理 \/ 数据字典负责人 Agent/);
  assert.match(doctored.stdout, /IAP \/ 订阅营收负责人 Agent/);
  assert.match(doctored.stdout, /医疗监管 \/ 健康声明审查负责人 Agent/);
  assert.match(doctored.stdout, /外部备案服务 \/ 云厂商支持 Agent/);
});

test('status summarizes agent board without full agent table', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath, '--write'], {
    encoding: 'utf8'
  });
  const status = spawnSync(process.execPath, [cli, 'status', workspace], { encoding: 'utf8' });
  const blockerLines = status.stdout.split('\n').filter((line) => line.startsWith('- '));

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.equal(status.status, 0, status.stdout + status.stderr);
  assert.ok(outputLineCount(status.stdout) <= 12);
  assert.ok(blockerLines.length <= 3);
  assert.match(status.stdout, /橘猫状态：需要处理（blocked）/);
  assert.match(status.stdout, /Agent 组：/);
  assert.match(status.stdout, /详情：governance\/agent-findings\.json/);
  assert.doesNotMatch(status.stdout, /App Store 上架负责人 Agent|后端工程师 Agent|医疗监管 \/ 健康声明审查负责人 Agent/);
});

test('doctor accepts not_sure answers without failing', () => {
  const workspace = createProductWorkspace();
  const answersPath = writeDoctorAnswersFile({
    launchIntent: 'not_sure',
    chargingPlan: 'not_sure'
  });

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(doctored.status, 0, doctored.stdout + doctored.stderr);
  assert.match(doctored.stdout, /现在不需要一次决定清楚，我会先按低风险路径处理/);
});

test('doctor exits when answers file is missing', () => {
  const workspace = createProductWorkspace();
  const missingAnswers = path.join(tempDir(), 'missing-answers.json');

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', missingAnswers], {
    encoding: 'utf8'
  });

  assert.equal(doctored.status, 1);
  assert.match(doctored.stderr, /answers 文件不存在/);
});

test('doctor exits for a directory that is not a Jumao workspace', () => {
  const workspace = tempDir();
  const answersPath = writeDoctorAnswersFile();

  const doctored = spawnSync(process.execPath, [cli, 'doctor', workspace, '--answers', answersPath], {
    encoding: 'utf8'
  });

  assert.equal(doctored.status, 1);
  assert.match(doctored.stderr, /请先运行 jumao new/);
});

test('check reports missing files', () => {
  const dir = tempDir();
  const checked = spawnSync(process.execPath, [cli, 'check', dir], { encoding: 'utf8' });
  assert.equal(checked.status, 1);
  assert.match(checked.stdout, /missing files/);
});
