import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const repoRoot = path.resolve(new URL('..', import.meta.url).pathname);
const cli = path.join(repoRoot, 'bin', 'jumao.js');

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'jumao-inspect-test-'));
}

function write(root, relativePath, content = '') {
  const output = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content, 'utf8');
}

function mkdir(root, relativePath) {
  fs.mkdirSync(path.join(root, relativePath), { recursive: true });
}

function inspect(root, args = []) {
  const result = spawnSync(process.execPath, [cli, 'inspect', root, '--json', ...args], { encoding: 'utf8' });
  return {
    ...result,
    json: result.status === 0 ? JSON.parse(result.stdout) : null
  };
}

function evidenceFiles(result) {
  return result.json.evidence.map((item) => item.file);
}

test('inspect identifies an empty directory without writing files', () => {
  const root = workspace();
  const before = fs.readdirSync(root);
  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.json.workspaceKind, 'empty');
  assert.equal(result.json.recommendedIntake.mode, 'new_project');
  assert.deepEqual(result.json.recommendedIntake.questions, [
    '你想做一个什么东西？',
    '第一版要让用户能完成哪些功能？',
    '这些功能里，哪一个最重要？',
    '第一版先做在哪个平台？'
  ]);
  assert.deepEqual(fs.readdirSync(root), before);
  assert.ok(result.json.evidence.some((item) => item.kind === 'workspace_kind'));
});

test('inspect identifies Jumao planning files as a new project', () => {
  const root = workspace();
  write(root, 'product/product-brief.zh-CN.md', '# 产品简报\n');
  write(root, 'proof/release-proof.zh-CN.md', '# 发布证明\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.workspaceKind, 'new');
  assert.equal(result.json.project.hasJumaoFiles, true);
  assert.equal(result.json.project.hasSourceCode, false);
  assert.ok(evidenceFiles(result).includes('product/product-brief.zh-CN.md'));
});

test('inspect identifies an Xcode and Swift project as existing with high iOS fit', () => {
  const root = workspace();
  mkdir(root, 'Focus.xcodeproj');
  write(root, 'Sources/FocusView.swift', 'import SwiftUI\nstruct FocusView {}\n');
  write(root, 'Tests/FocusTests.swift', 'import XCTest\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.workspaceKind, 'existing');
  assert.deepEqual(result.json.project.platforms, ['iOS']);
  assert.deepEqual(result.json.project.languages, ['Swift']);
  assert.deepEqual(result.json.project.buildSystems, ['Xcode']);
  assert.equal(result.json.project.hasSourceCode, true);
  assert.equal(result.json.project.hasTests, true);
  assert.equal(result.json.capabilityFit.level, 'high');
  assert.match(result.json.capabilityFit.message, /SwiftUI 与 Xcode/);
  assert.ok(result.json.evidence.some((item) => item.file === 'Focus.xcodeproj'));
});

test('inspect identifies a Node project as existing with limited fit', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'web-api', scripts: { prepare: 'touch should-not-exist' } }));
  write(root, 'src/index.js', 'export const ok = true;\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.workspaceKind, 'existing');
  assert.equal(result.json.project.name, 'web-api');
  assert.ok(result.json.project.languages.includes('JavaScript'));
  assert.ok(result.json.project.buildSystems.includes('npm'));
  assert.equal(result.json.capabilityFit.level, 'limited');
  assert.match(result.json.capabilityFit.message, /更擅长 iOS 原生 App/);
  assert.equal(fs.existsSync(path.join(root, 'should-not-exist')), false);
});

test('inspect does not write files or execute project scripts', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({
    name: 'read-only-project',
    scripts: { prepare: 'node -e "require(\'node:fs\').writeFileSync(\'script-ran\', \'yes\')"' }
  }));
  write(root, 'README.md', '# Read only\n');
  const before = directorySnapshot(root);

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(directorySnapshot(root), before);
  assert.equal(fs.existsSync(path.join(root, 'script-ran')), false);
});

test('inspect identifies an Android project as existing', () => {
  const root = workspace();
  write(root, 'settings.gradle', 'rootProject.name = "AndroidDemo"\n');
  write(root, 'app/build.gradle', 'plugins {}\n');
  write(root, 'app/src/main/java/MainActivity.java', 'class MainActivity {}\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.workspaceKind, 'existing');
  assert.ok(result.json.project.platforms.includes('Android'));
  assert.ok(result.json.project.languages.includes('Java'));
  assert.ok(result.json.project.buildSystems.includes('Gradle'));
  assert.equal(result.json.capabilityFit.level, 'limited');
});

test('inspect identifies a Flutter project as existing', () => {
  const root = workspace();
  write(root, 'pubspec.yaml', 'name: flutter_demo\n');
  write(root, 'lib/main.dart', 'void main() {}\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.workspaceKind, 'existing');
  assert.ok(result.json.project.platforms.includes('Flutter'));
  assert.ok(result.json.project.languages.includes('Dart'));
  assert.ok(result.json.project.buildSystems.includes('Flutter'));
});

test('inspect keeps multiple platforms, languages, and build systems for a mixed project', () => {
  const root = workspace();
  mkdir(root, 'Mixed.xcodeproj');
  write(root, 'ios/App.swift', 'import SwiftUI\n');
  write(root, 'package.json', JSON.stringify({ name: 'mixed', dependencies: { react: '1.0.0' } }));
  write(root, 'web/App.tsx', 'export const App = () => null;\n');
  write(root, 'android/build.gradle', 'plugins {}\n');
  write(root, 'android/MainActivity.kt', 'class MainActivity\n');

  const result = inspect(root);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual([...result.json.project.platforms].sort(), ['Android', 'Web', 'iOS']);
  assert.deepEqual([...result.json.project.languages].sort(), ['JavaScript', 'Kotlin', 'Swift', 'TypeScript']);
  assert.deepEqual([...result.json.project.buildSystems].sort(), ['Gradle', 'Xcode', 'npm']);
  assert.equal(result.json.capabilityFit.level, 'high');
});

test('inspect skips sensitive files, credentials, databases, dependencies, and generated output', () => {
  const root = workspace();
  write(root, '.env', 'API_TOKEN=do-not-read\n');
  write(root, 'api-secret.txt', 'do-not-read\n');
  write(root, 'private-key.pem', 'do-not-read\n');
  write(root, 'users.sqlite', 'do-not-read\n');
  write(root, 'node_modules/private/package.json', JSON.stringify({ name: 'hidden-node-project' }));
  write(root, 'DerivedData/Hidden.swift', 'struct Hidden {}\n');
  write(root, 'build/generated.js', 'export const generated = true;\n');
  write(root, 'dist/generated.js', 'export const generated = true;\n');
  write(root, 'Pods/Podfile', 'pod "Hidden"\n');

  const result = inspect(root);
  const output = result.stdout;

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.project.hasSourceCode, false);
  assert.equal(result.json.project.buildSystems.length, 0);
  assert.equal(output.includes('do-not-read'), false);
  assert.equal(output.includes('api-secret.txt'), false);
  assert.equal(output.includes('private-key.pem'), false);
  assert.equal(output.includes('users.sqlite'), false);
  assert.equal(output.includes('node_modules'), false);
  assert.equal(output.includes('DerivedData'), false);
});

test('inspect has stable parseable JSON and existing-project questions only ask for the requested change', () => {
  const root = workspace();
  write(root, 'package.json', JSON.stringify({ name: 'known-facts', dependencies: { react: '1.0.0' } }));
  write(root, 'README.md', '# Known Facts\n');
  const first = inspect(root);
  const second = inspect(root);

  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stderr, '');
  assert.deepEqual(first.json, second.json);
  assert.equal(first.json.schemaVersion, 1);
  assert.equal(first.json.recommendedIntake.mode, 'existing_project');
  assert.deepEqual(first.json.recommendedIntake.questions, [
    '这次你最想新增或修改什么？',
    '现在最卡你的问题是什么？',
    '哪些已经正常工作的部分不能改坏？'
  ]);
  assert.equal(first.json.recommendedIntake.questions.some((question) => /平台|语言|工程类型/.test(question)), false);
  assert.ok(first.json.evidence.some((item) => item.kind === 'project_file' && item.file === 'package.json'));
  assert.ok(first.json.evidence.some((item) => item.kind === 'workspace_kind'));
  assert.ok(first.json.evidence.some((item) => item.kind === 'capability_fit'));
});

test('inspect reports a missing workspace through stderr with a non-zero exit code', () => {
  const missing = path.join(os.tmpdir(), `jumao-inspect-missing-${process.pid}-${Date.now()}`);
  const result = spawnSync(process.execPath, [cli, 'inspect', missing, '--json'], { encoding: 'utf8' });

  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Workspace does not exist/);
});

function directorySnapshot(root) {
  const paths = [];
  const visit = (directory, relativeDirectory = '') => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
      const relativePath = relativeDirectory ? path.join(relativeDirectory, entry.name) : entry.name;
      paths.push(relativePath);
      if (entry.isDirectory()) visit(path.join(directory, entry.name), relativePath);
    }
  };
  visit(root);
  return paths;
}
