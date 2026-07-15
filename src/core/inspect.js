import fs from 'node:fs';
import path from 'node:path';

const MAX_ENTRIES = 400;
const MAX_DEPTH = 6;
const MAX_FILE_BYTES = 256 * 1024;

const skippedDirectories = new Set([
  '.git',
  'node_modules',
  'DerivedData',
  '.build',
  'build',
  'dist',
  'Pods',
  'coverage',
  '.next',
  'out',
  'target',
  'vendor',
  '.cache',
  '.gradle',
  '.dart_tool',
  'xcuserdata'
]);

const sensitiveNamePattern = /(^\.env(?:\.|$)|secret|token|credential|private[-_]?key)/i;
const sensitiveExtensions = new Set(['.pem', '.key', '.p12', '.pfx', '.cer', '.crt', '.der', '.db', '.sqlite', '.sqlite3', '.mdb']);
const binaryExtensions = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic', '.ico', '.icns', '.pdf', '.zip', '.gz', '.tgz',
  '.dmg', '.app', '.framework', '.xcarchive', '.a', '.dylib', '.so', '.dll', '.exe', '.mp3', '.mp4', '.mov'
]);

const sourceExtensions = new Map([
  ['.swift', { language: 'Swift', platform: 'iOS' }],
  ['.m', { language: 'Objective-C', platform: 'iOS' }],
  ['.mm', { language: 'Objective-C++', platform: 'iOS' }],
  ['.js', { language: 'JavaScript' }],
  ['.jsx', { language: 'JavaScript', platform: 'Web' }],
  ['.ts', { language: 'TypeScript' }],
  ['.tsx', { language: 'TypeScript', platform: 'Web' }],
  ['.kt', { language: 'Kotlin', platform: 'Android' }],
  ['.java', { language: 'Java', platform: 'Android' }],
  ['.dart', { language: 'Dart', platform: 'Flutter' }],
  ['.py', { language: 'Python', platform: 'Backend' }],
  ['.rs', { language: 'Rust', platform: 'Backend' }],
  ['.go', { language: 'Go', platform: 'Backend' }],
  ['.cs', { language: 'C#', platform: 'Backend' }],
  ['.rb', { language: 'Ruby', platform: 'Backend' }],
  ['.php', { language: 'PHP', platform: 'Backend' }]
]);

const manifestFacts = new Map([
  ['Package.swift', { language: 'Swift', buildSystem: 'SwiftPM' }],
  ['Podfile', { platform: 'iOS', buildSystem: 'CocoaPods' }],
  ['requirements.txt', { language: 'Python', platform: 'Backend', buildSystem: 'pip' }],
  ['pyproject.toml', { language: 'Python', platform: 'Backend', buildSystem: 'pip' }],
  ['Cargo.toml', { language: 'Rust', platform: 'Backend', buildSystem: 'Cargo' }],
  ['go.mod', { language: 'Go', platform: 'Backend', buildSystem: 'Go modules' }],
  ['build.gradle', { platform: 'Android', buildSystem: 'Gradle' }],
  ['settings.gradle', { platform: 'Android', buildSystem: 'Gradle' }],
  ['pubspec.yaml', { language: 'Dart', platform: 'Flutter', buildSystem: 'Flutter' }],
  ['project.yml', { buildSystem: 'XcodeGen' }]
]);

const newProjectQuestions = [
  '你想做个什么？',
  '你希望它能做哪些事？',
  '你想先在哪儿用它？'
];

const existingProjectQuestions = [
  '这次你想让它变成什么样？'
];

export function inspectWorkspace(workspace) {
  const workspacePath = path.resolve(workspace);
  if (!fs.existsSync(workspacePath)) {
    return { ok: false, message: `Workspace does not exist: ${workspacePath}` };
  }

  let rootStat;
  try {
    rootStat = fs.statSync(workspacePath);
  } catch {
    return { ok: false, message: `Workspace cannot be read: ${workspacePath}` };
  }
  if (!rootStat.isDirectory()) {
    return { ok: false, message: `Workspace is not a directory: ${workspacePath}` };
  }

  const state = createScanState(workspacePath);
  scanDirectory(workspacePath, '', 0, state);
  const result = buildResult(state);
  return { ok: true, result, warnings: state.warnings };
}

function createScanState(workspacePath) {
  return {
    workspacePath,
    scannedEntries: 0,
    visibleEntries: 0,
    warnings: [],
    evidence: [],
    platforms: new Set(),
    languages: new Set(),
    buildSystems: new Set(),
    hasSourceCode: false,
    hasTests: false,
    hasJumaoFiles: false,
    hasExistingEvidence: false,
    hasUnclassifiedVisibleFile: false,
    projectName: ''
  };
}

function scanDirectory(directory, relativeDirectory, depth, state) {
  if (depth > MAX_DEPTH) {
    addWarning(state, `扫描深度已达到上限 ${MAX_DEPTH}：${relativeDirectory || '.'}`);
    return;
  }

  let entries;
  try {
    entries = fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name));
  } catch {
    addWarning(state, `无法读取目录：${relativeDirectory || '.'}`);
    return;
  }

  for (const entry of entries) {
    if (state.scannedEntries >= MAX_ENTRIES) {
      addWarning(state, `扫描文件数已达到上限 ${MAX_ENTRIES}`);
      return;
    }

    state.scannedEntries += 1;
    const relativePath = relativeDirectory ? path.posix.join(relativeDirectory, entry.name) : entry.name;
    const fullPath = path.join(directory, entry.name);
    const hiddenEntry = entry.name.startsWith('.');
    if (hiddenEntry) {
      if (entry.isDirectory() && entry.name === '.jumao') markJumao(state, relativePath);
      continue;
    }
    state.visibleEntries += 1;

    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      if (shouldSkipDirectory(entry.name)) continue;
      if (entry.name.endsWith('.xcodeproj') || entry.name.endsWith('.xcworkspace')) {
        addEvidence(state, 'project_file', relativePath, '检测到 Xcode 工程');
        if (!state.projectName) {
          state.projectName = entry.name.endsWith('.xcodeproj')
            ? path.basename(entry.name, '.xcodeproj')
            : path.basename(entry.name, '.xcworkspace');
          addEvidence(state, 'project_name', relativePath, '项目名称来自 Xcode 工程文件名');
        }
        addFact(state, { platform: 'iOS', buildSystem: 'Xcode' });
        state.hasExistingEvidence = true;
        continue;
      }
      if (isJumaoDirectory(entry.name, relativePath)) markJumao(state, relativePath);
      scanDirectory(fullPath, relativePath, depth + 1, state);
      continue;
    }

    if (!entry.isFile() || shouldSkipFile(entry.name)) continue;
    inspectFile(fullPath, relativePath, entry.name, state);
  }
}

function inspectFile(fullPath, relativePath, name, state) {
  if (isJumaoFile(name, relativePath)) {
    markJumao(state, relativePath);
    return;
  }
  if (isTestFile(name, relativePath)) {
    state.hasTests = true;
    addEvidence(state, 'test_file', relativePath, '检测到测试代码或测试目录中的文件');
  }

  const extension = path.extname(name).toLowerCase();
  const sourceFact = sourceExtensions.get(extension);
  if (sourceFact) {
    state.hasSourceCode = true;
    state.hasExistingEvidence = true;
    addFact(state, sourceFact);
    addEvidence(state, 'source_file', relativePath, `检测到 ${sourceFact.language} 源代码`);
  }

  if (name === 'package.json') {
    state.hasExistingEvidence = true;
    addFact(state, { language: 'JavaScript', buildSystem: 'npm' });
    addEvidence(state, 'project_file', relativePath, '检测到 Node 项目清单');
    inspectPackageManifest(fullPath, relativePath, state);
    return;
  }

  const manifestFact = manifestFacts.get(name);
  if (manifestFact) {
    state.hasExistingEvidence = true;
    addFact(state, manifestFact);
    addEvidence(state, 'project_file', relativePath, `检测到 ${name} 工程配置`);
    return;
  }

  state.hasUnclassifiedVisibleFile = true;
}

function inspectPackageManifest(fullPath, relativePath, state) {
  const text = readSmallTextFile(fullPath, relativePath, state);
  if (text === null) return;

  try {
    const manifest = JSON.parse(text);
    if (typeof manifest.name === 'string' && manifest.name.trim()) {
      state.projectName = manifest.name.trim();
      addEvidence(state, 'project_name', relativePath, '项目名称来自 package.json 的 name');
    }
    const dependencies = {
      ...(manifest.dependencies || {}),
      ...(manifest.devDependencies || {})
    };
    if (dependencies['react-native']) addFact(state, { platform: 'React Native' });
    else if (dependencies.react || dependencies.next) addFact(state, { platform: 'Web' });
    else addFact(state, { platform: 'Backend' });
  } catch {
    addWarning(state, `无法解析允许读取的配置：${relativePath}`);
  }
}

function readSmallTextFile(fullPath, relativePath, state) {
  let stat;
  try {
    stat = fs.statSync(fullPath);
  } catch {
    addWarning(state, `无法读取文件信息：${relativePath}`);
    return null;
  }
  if (stat.size > MAX_FILE_BYTES) {
    addWarning(state, `文件超过读取上限 ${MAX_FILE_BYTES} 字节：${relativePath}`);
    return null;
  }
  try {
    return fs.readFileSync(fullPath, 'utf8');
  } catch {
    addWarning(state, `无法读取允许的配置：${relativePath}`);
    return null;
  }
}

function buildResult(state) {
  const workspaceKind = state.visibleEntries === 0
    ? 'empty'
    : (state.hasExistingEvidence ? 'existing' : (state.hasUnclassifiedVisibleFile ? 'unknown' : 'new'));
  const isIOSNative = state.platforms.has('iOS') || state.languages.has('Swift') || state.buildSystems.has('Xcode');
  const capabilityFit = isIOSNative
    ? {
        level: 'high',
        primaryFocus: 'ios_native',
        message: '橘猫对这个项目类型比较熟悉。当前的问题库、模板和检查规则主要针对 Swift、SwiftUI 与 Xcode 项目。'
      }
    : {
        level: 'limited',
        primaryFocus: 'ios_native',
        message: '橘猫目前更擅长 iOS 原生 App。这个项目仍然可以扫描和梳理，但部分问题、模板和检查规则可能不完整，需要额外判断。'
      };

  addEvidence(
    state,
    'workspace_kind',
    '.',
    workspaceKind === 'empty'
      ? '目录为空或仅包含系统隐藏文件'
      : (workspaceKind === 'new'
          ? '仅发现空目录结构或 Jumao 初始化文件'
          : (workspaceKind === 'unknown' ? '未找到足够的工程或源代码证据，等待用户选择用途' : '检测到真实开发证据'))
  );
  addEvidence(state, 'capability_fit', '.', isIOSNative ? '检测到 iOS、Swift 或 Xcode 证据' : '未检测到 iOS、Swift 或 Xcode 证据');

  return {
    schemaVersion: 1,
    workspaceKind,
    project: {
      name: state.projectName,
      platforms: [...state.platforms],
      languages: [...state.languages],
      buildSystems: [...state.buildSystems],
      hasSourceCode: state.hasSourceCode,
      hasTests: state.hasTests,
      hasJumaoFiles: state.hasJumaoFiles
    },
    capabilityFit,
    evidence: state.evidence,
    unknowns: unknownsFor(state, workspaceKind),
    recommendedIntake: {
      mode: workspaceKind === 'existing'
        ? 'existing_project'
        : (workspaceKind === 'unknown' ? 'choose_project_type' : 'new_project'),
      questions: workspaceKind === 'existing'
        ? existingProjectQuestions
        : (workspaceKind === 'unknown' ? [] : newProjectQuestions)
    }
  };
}

function unknownsFor(state, workspaceKind) {
  if (workspaceKind === 'empty') return ['尚未发现项目文件，因此平台、技术栈和现有功能未知。'];
  if (workspaceKind === 'unknown') return ['未找到足够证据判断这是新项目还是已有项目，请先由项目主人选择。'];
  const unknowns = ['未读取业务代码内容，现有功能细节仍未知。'];
  if (state.platforms.size === 0 && state.languages.size === 0) {
    unknowns.unshift('未检测到可安全读取的工程配置，平台和语言仍未知。');
  }
  return unknowns;
}

function addFact(state, fact) {
  if (fact.platform) state.platforms.add(fact.platform);
  if (fact.language) state.languages.add(fact.language);
  if (fact.buildSystem) state.buildSystems.add(fact.buildSystem);
}

function addEvidence(state, kind, file, detail) {
  if (state.evidence.some((item) => item.kind === kind && item.file === file && item.detail === detail)) return;
  state.evidence.push({ kind, file, detail });
}

function addWarning(state, warning) {
  if (!state.warnings.includes(warning)) state.warnings.push(warning);
}

function markJumao(state, relativePath) {
  state.hasJumaoFiles = true;
  addEvidence(state, 'jumao_file', relativePath, '检测到 Jumao 模板、规划或治理文件');
}

function shouldSkipDirectory(name) {
  return skippedDirectories.has(name) || sensitiveNamePattern.test(name);
}

function shouldSkipFile(name) {
  const extension = path.extname(name).toLowerCase();
  return sensitiveNamePattern.test(name) || sensitiveExtensions.has(extension) || binaryExtensions.has(extension);
}

function isJumaoDirectory(name, relativePath) {
  return name === 'product' || name === 'proof' || name === 'templates' || relativePath === '.jumao';
}

function isJumaoFile(name, relativePath) {
  return name === 'AGENTS.md' || name === 'CLAUDE.md' || relativePath.startsWith('product/') || relativePath.startsWith('proof/');
}

function isTestFile(name, relativePath) {
  return /(^|\/)(test|tests|__tests__)\//i.test(relativePath)
    || /(?:\.test|\.spec)\.[cm]?[jt]sx?$/i.test(name)
    || /Tests\.(?:swift|m|mm|kt|java)$/i.test(name);
}
