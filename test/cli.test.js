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
