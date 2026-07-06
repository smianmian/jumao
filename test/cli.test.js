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

test('check reports missing files', () => {
  const dir = tempDir();
  const checked = spawnSync(process.execPath, [cli, 'check', dir], { encoding: 'utf8' });
  assert.equal(checked.status, 1);
  assert.match(checked.stdout, /missing files/);
});
