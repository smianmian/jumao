import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { agentGroups, responsibilityAgents } from './agent-registry.js';
import { inspectWorkspace } from './inspect.js';
import { writePlanningStatus } from './status.js';

const runtimeSchemaVersion = 1;
const intakePath = '.jumao/intake-answers.json';
const latestRunPath = '.jumao/latest-run.json';
const publishedTaskPlanPath = 'tasks/jumao-agent-plan.md';
const validAgentStatuses = new Set(['completed', 'skipped', 'blocked', 'failed']);
const alwaysRelevantAgentIds = new Set([
  'founder_decision',
  'product_manager',
  'ui_ux',
  'security_privacy',
  'qa_testing',
  'project_tech_lead',
  'release_manager',
  'documentation_delivery'
]);

const skippedDirectories = new Set([
  '.git', '.jumao', 'node_modules', 'DerivedData', '.build', 'build', 'dist', 'Pods',
  'coverage', '.next', 'out', 'target', 'vendor', '.cache', '.gradle', '.dart_tool',
  'xcuserdata', 'tmp'
]);
const sensitiveNamePattern = /(^\.env(?:\.|$)|secret|token|credential|private[-_]?key|password|passwd)/i;
const sensitiveExtensions = new Set([
  '.pem', '.key', '.p12', '.pfx', '.cer', '.crt', '.der', '.db', '.sqlite', '.sqlite3', '.mdb'
]);
const binaryExtensions = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic', '.ico', '.icns', '.pdf', '.zip', '.gz', '.tgz',
  '.dmg', '.app', '.framework', '.xcarchive', '.a', '.dylib', '.so', '.dll', '.exe', '.mp3', '.mp4', '.mov'
]);
const sourceExtensions = new Set([
  '.swift', '.m', '.mm', '.h', '.js', '.jsx', '.ts', '.tsx', '.py', '.rs', '.go', '.cs',
  '.rb', '.php', '.kt', '.java', '.dart', '.html', '.css', '.scss', '.vue', '.svelte'
]);
const testPathPattern = /(^|\/)(test|tests|__tests__)\/|(?:\.test|\.spec)\.[cm]?[jt]sx?$|Tests\.(?:swift|m|mm|kt|java)$/i;
const configNames = new Set([
  'package.json', 'Package.swift', 'Podfile', 'requirements.txt', 'pyproject.toml', 'Cargo.toml',
  'go.mod', 'build.gradle', 'settings.gradle', 'pubspec.yaml', 'project.yml', 'Makefile'
]);

const signalAgentMap = {
  iphone: ['ios_engineer', 'cicd_build', 'accessibility'],
  web: ['website_frontend', 'accessibility'],
  watch: ['watchos_engineer', 'device_lab_test_data'],
  login: [
    'backend_engineer', 'database_engineer', 'data_governance_dictionary', 'privacy_request_ops',
    'security_privacy', 'support_operations', 'admin_dashboard_product'
  ],
  payment: ['finance_tax', 'iap_revenue_ops', 'support_operations', 'legal_compliance'],
  cloud: ['backend_engineer', 'database_engineer', 'devops_cloud', 'data_governance_dictionary', 'sre_stability'],
  health: [
    'health_content', 'medical_claims_review', 'algorithm_validation_evidence', 'algorithm_data',
    'security_privacy', 'sdk_vendor_governance', 'device_lab_test_data'
  ],
  sensitive: ['security_privacy', 'data_governance_dictionary', 'privacy_request_ops', 'legal_compliance'],
  china: [
    'legal_compliance', 'filing_cloud_vendor_support', 'website_frontend', 'wechat_open_platform',
    'sms_service', 'corporate_admin'
  ],
  release: [
    'release_manager', 'qa_testing', 'cicd_build', 'app_store_submission', 'sre_stability',
    'remote_config_gray_release', 'device_lab_test_data'
  ],
  analytics: ['analytics_growth', 'sdk_vendor_governance', 'data_governance_dictionary'],
  messaging: ['sms_service', 'wechat_open_platform', 'sdk_vendor_governance', 'abuse_risk_control'],
  algorithm: ['algorithm_data', 'algorithm_validation_evidence'],
  company: ['corporate_admin', 'software_copyright_qualification', 'procurement_contract_vendor'],
  brand: ['brand_copywriting', 'ip_trademark'],
  publicUsers: [
    'user_research_positioning', 'design_system_qa', 'accessibility', 'legal_compliance',
    'sre_stability', 'remote_config_gray_release'
  ],
  thirdParty: ['sdk_vendor_governance', 'procurement_contract_vendor'],
  abuse: ['abuse_risk_control'],
  support: ['support_operations', 'privacy_request_ops', 'admin_dashboard_product']
};

export function planWorkspace(workspace, options = {}) {
  const workspacePath = path.resolve(workspace);
  if (!isReadableDirectory(workspacePath)) {
    return failedResult(`Workspace does not exist or is not a readable directory: ${workspacePath}`);
  }

  const startedAt = nowISO(options);
  const runId = makeRunId(startedAt, options);
  const runRelativePath = path.posix.join('.jumao', 'runs', runId);
  const runPath = path.join(workspacePath, runRelativePath);
  let context;
  let execution;
  let checkingWritten = false;

  try {
    const intake = readIntake(workspacePath);
    const inspection = inspectWorkspace(workspacePath);
    if (!inspection.ok) throw new Error(inspection.message);
    const inventory = collectWorkspaceInventory(workspacePath);
    context = buildContext(workspacePath, intake, inspection.result, inventory);
    context.inputFingerprint = inputFingerprint(context);

    if (!options.force) {
      const reused = reusableResult(workspacePath, context.inputFingerprint);
      if (reused) return reused;
    }

    ensureRunDirectories(runPath);
    writePlanningStatus(workspacePath, 'checking', {
      runId,
      startedAt,
      completedAt: null,
      totalAgents: responsibilityAgents.length,
      completedAgents: 0,
      skippedAgents: 0,
      blockedAgents: 0,
      failedAgents: 0,
      groups: [],
      runPath: runRelativePath,
      blockingQuestions: []
    });
    checkingWritten = true;

    execution = executePipeline(context, { runId, startedAt, now: options.now });
    const completedAt = nowISO(options);
    execution.completedAt = completedAt;
    execution.counts = countAgentStatuses(execution.agents);
    execution.state = finalState(execution.counts);

    const taskPlan = synthesizeTaskPlan(context, execution);
    writeRunArtifacts(runPath, context, execution, taskPlan);
    publishTaskPlan(workspacePath, runPath, taskPlan.markdown);
    writeLatestRun(workspacePath, context, execution, runRelativePath);
    writePlanningStatus(workspacePath, execution.state, statusRun(execution, runRelativePath));

    return resultFromExecution(execution, runRelativePath, false);
  } catch (error) {
    const message = safeErrorMessage(error);
    if (checkingWritten && context) {
      try {
        const failedExecution = executionAfterFailure(context, execution, {
          runId,
          startedAt,
          completedAt: nowISO(options),
          message
        });
        writeFailureArtifacts(runPath, context, failedExecution);
        writeLatestRun(workspacePath, context, failedExecution, runRelativePath);
        writePlanningStatus(workspacePath, 'blocked', statusRun(failedExecution, runRelativePath));
        return resultFromExecution(failedExecution, runRelativePath, false, message);
      } catch {
        try {
          writePlanningStatus(workspacePath, 'blocked', {
            runId,
            startedAt,
            completedAt: nowISO(options),
            totalAgents: responsibilityAgents.length,
            completedAgents: 0,
            skippedAgents: 0,
            blockedAgents: 0,
            failedAgents: 1,
            groups: [],
            runPath: runRelativePath,
            blockingQuestions: [],
            error: message
          });
        } catch {
          // The workspace itself is no longer writable; the returned error remains authoritative.
        }
      }
    }
    return failedResult(message, { runId, runPath: runRelativePath });
  }
}

function readIntake(workspacePath) {
  const fullPath = path.join(workspacePath, intakePath);
  if (!fs.existsSync(fullPath)) {
    return { state: 'missing', mode: null, answers: {}, sourcePath: intakePath };
  }

  try {
    const document = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
    const normalized = normalizeIntake(document);
    return { state: 'valid', ...normalized, sourcePath: intakePath, raw: document };
  } catch (error) {
    return {
      state: 'corrupt',
      mode: null,
      answers: {},
      sourcePath: intakePath,
      error: `无法解析 ${intakePath}：${safeErrorMessage(error)}`
    };
  }
}

function normalizeIntake(document) {
  if (!document || typeof document !== 'object' || Array.isArray(document)) {
    throw new Error('根节点必须是 JSON 对象');
  }

  if (document.mode === 'new_project' || document.mode === 'existing_project') {
    return {
      schemaVersion: Number(document.schemaVersion) || 1,
      mode: document.mode,
      answers: document.mode === 'new_project'
        ? normalizeNewAnswers(document.answers || {})
        : normalizeExistingAnswers(document.answers || {})
    };
  }
  if (document.newProject && typeof document.newProject === 'object') {
    return { schemaVersion: 1, mode: 'new_project', answers: normalizeNewAnswers(document.newProject) };
  }
  if (document.existingProject && typeof document.existingProject === 'object') {
    return { schemaVersion: 1, mode: 'existing_project', answers: normalizeExistingAnswers(document.existingProject) };
  }
  throw new Error('缺少受支持的 new_project 或 existing_project 模式');
}

function normalizeNewAnswers(answers) {
  const idea = textValue(answers.idea) || textValue(answers.project) || textValue(answers.projectSummary);
  const features = textValue(answers.features)
    || listValue(answers.coreFeatures)
    || textValue(answers.firstVersion)
    || textValue(answers.goal)
    || textValue(answers.primaryGoal);
  const rawPlatform = textValue(answers.platform) || textValue(answers.targetPlatform);
  const platform = normalizePlatform(rawPlatform);
  return { idea, features, platform };
}

function normalizeExistingAnswers(answers) {
  return {
    requestedChange: textValue(answers.requestedChange)
      || textValue(answers.change)
      || textValue(answers.changeGoal)
      || textValue(answers.idea)
  };
}

function normalizePlatform(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (['iphone', 'ios', 'iphone / ipad', 'iphone/ipad'].includes(normalized)) return 'iPhone';
  if (['mac', 'macos'].includes(normalized)) return 'Mac';
  if (['网页', 'web', 'website'].includes(normalized)) return '网页';
  if (['还没想好', 'undecided', 'unknown', ''].includes(normalized)) return normalized ? '还没想好' : '';
  return '';
}

function collectWorkspaceInventory(workspacePath) {
  const files = [];
  const warnings = [];
  scanInventory(workspacePath, '', 0, files, warnings);
  files.sort((left, right) => left.path.localeCompare(right.path));
  return {
    files,
    warnings,
    sourceFiles: files.filter((file) => file.kind === 'source').map((file) => file.path),
    testFiles: files.filter((file) => file.kind === 'test').map((file) => file.path),
    configFiles: files.filter((file) => file.kind === 'config').map((file) => file.path),
    productFiles: files.filter((file) => file.kind === 'product').map((file) => file.path),
    proofFiles: files.filter((file) => file.kind === 'proof').map((file) => file.path)
  };
}

function scanInventory(directory, relativeDirectory, depth, files, warnings) {
  if (depth > 7 || files.length >= 600) return;
  let entries;
  try {
    entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name));
  } catch {
    warnings.push(`无法读取目录：${relativeDirectory || '.'}`);
    return;
  }

  for (const entry of entries) {
    if (files.length >= 600) break;
    const relativePath = relativeDirectory ? path.posix.join(relativeDirectory, entry.name) : entry.name;
    if (relativePath === publishedTaskPlanPath) continue;
    if (entry.name.startsWith('.') && entry.name !== '.github') continue;
    if (sensitiveNamePattern.test(entry.name)) continue;
    const fullPath = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      if (skippedDirectories.has(entry.name)) continue;
      scanInventory(fullPath, relativePath, depth + 1, files, warnings);
      continue;
    }
    if (!entry.isFile() || shouldSkipInventoryFile(entry.name)) continue;
    const file = inventoryFile(fullPath, relativePath);
    if (file) files.push(file);
  }
}

function inventoryFile(fullPath, relativePath) {
  let stat;
  try {
    stat = fs.statSync(fullPath);
  } catch {
    return null;
  }
  const kind = inventoryKind(relativePath);
  let content = '';
  let contentHash = null;
  if (stat.size <= 256 * 1024 && kind !== 'other') {
    try {
      content = fs.readFileSync(fullPath, 'utf8');
      contentHash = hashText(content);
    } catch {
      content = '';
    }
  }
  return {
    path: relativePath,
    kind,
    size: stat.size,
    contentHash,
    searchText: content.toLowerCase()
  };
}

function inventoryKind(relativePath) {
  if (relativePath.startsWith('product/')) return 'product';
  if (relativePath.startsWith('proof/')) return 'proof';
  const name = path.posix.basename(relativePath);
  if (testPathPattern.test(relativePath)) return 'test';
  if (configNames.has(name) || /\.xcodeproj\//.test(relativePath)) return 'config';
  if (sourceExtensions.has(path.extname(name).toLowerCase())) return 'source';
  if (/\.(md|txt|json|ya?ml|toml)$/i.test(name)) return 'document';
  return 'other';
}

function shouldSkipInventoryFile(name) {
  const extension = path.extname(name).toLowerCase();
  return sensitiveExtensions.has(extension) || binaryExtensions.has(extension);
}

function buildContext(workspacePath, intake, inspection, inventory) {
  const answerText = Object.values(intake.answers || {}).filter((value) => typeof value === 'string').join('\n');
  const signals = detectSignals(answerText, intake, inspection);
  const impactFiles = findImpactFiles(inventory, answerText);
  const documentedProtections = findDocumentedProtections(inventory);
  const blockingQuestions = blockingQuestionsFor(intake);
  return {
    workspacePath,
    intake,
    inspection,
    inventory,
    signals,
    impactFiles,
    documentedProtections,
    blockingQuestions
  };
}

function detectSignals(answerText, intake, inspection) {
  const value = answerText.toLowerCase();
  const has = (pattern) => pattern.test(value);
  const platform = intake.mode === 'new_project' ? intake.answers.platform : '';
  const project = inspection.project || {};
  return {
    iphone: platform === 'iPhone' || (project.platforms || []).includes('iOS'),
    mac: platform === 'Mac' || (project.platforms || []).includes('macOS'),
    web: platform === '网页' || (project.platforms || []).includes('Web'),
    watch: has(/watch|手表|心率/),
    login: has(/登录|账号|账户|注册|sign[ -]?in|account/),
    payment: has(/支付|付费|收费|订阅|会员|购买|退款|payment|subscription|purchase/),
    cloud: has(/云|同步|换机|服务端|后端|服务器|cloud|sync|backend/),
    health: has(/健康|医疗|诊断|治疗|睡眠|心率|血压|health|medical/),
    sensitive: has(/身份证|手机号|定位|通讯录|隐私|敏感|儿童|照片|privacy|location|contact/),
    china: has(/中国大陆|大陆用户|备案|微信|短信|china/),
    release: has(/发布|上架|app store|testflight|提审|上线|release/),
    analytics: has(/统计|分析|留存|转化|analytics/),
    messaging: has(/微信|短信|验证码|wechat|sms/),
    algorithm: has(/算法|评分|预测|推荐|报告|趋势|algorithm|score|predict/),
    company: has(/公司|企业|商业化|融资|company|business/),
    brand: has(/品牌|商标|图标|名称|brand|trademark/),
    publicUsers: has(/公开|用户|朋友|客户|上线|public/),
    thirdParty: has(/第三方|供应商|sdk|外包|vendor/),
    abuse: has(/防刷|滥用|验证码|公开入口|abuse/),
    support: has(/客服|退款|注销|反馈|support/)
  };
}

function findImpactFiles(inventory, answerText) {
  const tokens = searchTokens(answerText);
  if (tokens.length === 0) return [];
  const ranked = [];
  for (const file of inventory.files) {
    if (!['source', 'test', 'config', 'product', 'proof'].includes(file.kind)) continue;
    const pathText = file.path.toLowerCase();
    const matches = tokens.filter((token) => pathText.includes(token) || file.searchText.includes(token));
    if (matches.length > 0) ranked.push({ path: file.path, kind: file.kind, matches: [...new Set(matches)] });
  }
  return ranked
    .sort((left, right) => right.matches.length - left.matches.length || left.path.localeCompare(right.path))
    .slice(0, 12);
}

function findDocumentedProtections(inventory) {
  const protections = [];
  for (const file of inventory.files.filter((item) => item.kind === 'product' || item.kind === 'proof')) {
    if (!file.searchText) continue;
    const lines = file.searchText.split('\n');
    lines.forEach((line, index) => {
      const trimmed = line.trim().replace(/^[-*]\s*/, '');
      if (!trimmed || !/(必须|不要|不能|不得|保留|不修改|must|do not|keep)/i.test(trimmed)) return;
      protections.push({ source: `${file.path}:${index + 1}`, statement: trimmed });
    });
  }
  return protections.slice(0, 20);
}

function blockingQuestionsFor(intake) {
  if (intake.state === 'corrupt') return ['请重新完成首轮问答，当前答案文件无法读取。'];
  if (intake.state === 'missing') return ['请先在 Jumao Cat 或 jumao interview 中完成首轮问答。'];
  if (intake.mode === 'new_project') {
    const questions = [];
    if (!intake.answers.idea) questions.push('你想做个什么？');
    if (!intake.answers.features) questions.push('你希望它能做哪些事？');
    if (!intake.answers.platform || intake.answers.platform === '还没想好') questions.push('你想先在哪儿用它？');
    return questions;
  }
  return intake.answers.requestedChange ? [] : ['这次你想让它变成什么样？'];
}

function executePipeline(context, run) {
  const agents = [];
  const groups = [];
  let previousHandoff = null;

  for (let index = 0; index < agentGroups.length; index += 1) {
    const group = agentGroups[index];
    const groupStartedAt = nowISO({ now: run.now });
    const timer = performance.now();
    const groupAgents = responsibilityAgents
      .filter((agent) => agent.groupId === group.id)
      .map((agent) => executeAgent(agent, context));
    agents.push(...groupAgents);
    const counts = countAgentStatuses(groupAgents);
    const findings = unique(groupAgents.flatMap((agent) => agent.findings)).slice(0, 12);
    const protections = unique(groupAgents.flatMap((agent) => agent.protections)).slice(0, 12);
    const tasks = unique(groupAgents.flatMap((agent) => agent.tasks)).slice(0, 12);
    const handoff = {
      fromGroupId: group.id,
      findings,
      protections,
      tasks,
      blockingQuestions: unique(groupAgents.flatMap((agent) => agent.blockingQuestions))
    };
    groups.push({
      groupId: group.id,
      groupName: group.name,
      sequence: index + 1,
      executionMode: 'sequential',
      dependsOnGroupId: index === 0 ? null : agentGroups[index - 1].id,
      startedAt: groupStartedAt,
      completedAt: nowISO({ now: run.now }),
      durationMs: Math.max(0, Math.round((performance.now() - timer) * 1000) / 1000),
      participatingAgents: groupAgents.filter((agent) => agent.status !== 'skipped').map((agent) => agent.agentId),
      agentStatuses: groupAgents.map((agent) => ({ agentId: agent.agentId, status: agent.status })),
      counts,
      mainFindings: findings,
      boundaries: unique(groupAgents.flatMap((agent) => agent.decisions)).slice(0, 12),
      protections,
      receivedContext: previousHandoff,
      handoff
    });
    previousHandoff = handoff;
  }

  return {
    schemaVersion: runtimeSchemaVersion,
    runId: run.runId,
    startedAt: run.startedAt,
    completedAt: null,
    executionMode: 'sequential',
    agents,
    groups,
    counts: countAgentStatuses(agents),
    state: 'checking'
  };
}

function executeAgent(agent, context) {
  const base = {
    agentId: agent.id,
    groupId: agent.groupId,
    status: 'skipped',
    summary: '',
    evidence: [],
    findings: [],
    decisions: [],
    protections: [],
    tasks: [],
    blockingQuestions: [],
    skippedReason: null,
    error: null
  };

  if (context.intake.state === 'corrupt') {
    if (agent.id === 'founder_decision') {
      return {
        ...base,
        status: 'failed',
        summary: '首轮答案解析失败，无法建立可靠的需求基线。',
        evidence: [{ source: intakePath, detail: '文件存在但不是可用的问答 JSON。' }],
        blockingQuestions: context.blockingQuestions,
        error: context.intake.error
      };
    }
    if (alwaysRelevantAgentIds.has(agent.id)) {
      return {
        ...base,
        status: 'blocked',
        summary: '缺少可读取的首轮答案，当前职责无法做出可靠判断。',
        evidence: [{ source: intakePath, detail: '问答 JSON 损坏。' }],
        blockingQuestions: context.blockingQuestions
      };
    }
    return skippedAgent(base, '首轮答案损坏，且没有真实证据表明当前项目需要该职责。');
  }

  if (context.intake.state === 'missing') {
    if (alwaysRelevantAgentIds.has(agent.id)) {
      return {
        ...base,
        status: 'blocked',
        summary: '首轮需求尚未提供，无法形成可交付的开发计划。',
        evidence: [{ source: intakePath, detail: '未找到首轮答案文件。' }],
        blockingQuestions: context.blockingQuestions
      };
    }
    return skippedAgent(base, '没有首轮答案，也没有项目证据触发该职责。');
  }

  const relevantReasons = relevanceReasons(agent, context);
  if (relevantReasons.length === 0) {
    return skippedAgent(base, '用户答案、只读扫描和项目文件中没有发现与该职责相关的证据。');
  }

  if (context.blockingQuestions.length > 0 && blocksAgent(agent, context)) {
    return {
      ...base,
      status: 'blocked',
      summary: '缺少会直接影响当前实现方向的信息，暂不能完成该职责判断。',
      evidence: evidenceFor(agent, context, relevantReasons),
      blockingQuestions: context.blockingQuestions
    };
  }

  const analysis = analyzeAgent(agent, context, relevantReasons);
  return {
    ...base,
    status: 'completed',
    summary: analysis.summary,
    evidence: evidenceFor(agent, context, relevantReasons),
    findings: analysis.findings,
    decisions: analysis.decisions,
    protections: analysis.protections,
    tasks: analysis.tasks
  };
}

function relevanceReasons(agent, context) {
  const reasons = [];
  if (alwaysRelevantAgentIds.has(agent.id)) reasons.push('runtime-baseline');
  for (const [signal, ids] of Object.entries(signalAgentMap)) {
    if (context.signals[signal] && ids.includes(agent.id)) reasons.push(`signal:${signal}`);
  }
  if (context.intake.mode === 'existing_project') {
    if (agent.id === 'cicd_build' && context.inventory.configFiles.length > 0) reasons.push('existing-config');
    if (agent.id === 'design_system_qa' && /界面|页面|ui|view/i.test(context.intake.answers.requestedChange)) reasons.push('existing-ui-change');
  }
  return unique(reasons);
}

function blocksAgent(agent, context) {
  if (context.intake.mode === 'existing_project') return !context.intake.answers.requestedChange;
  if (!context.intake.answers.idea || !context.intake.answers.features) {
    return alwaysRelevantAgentIds.has(agent.id);
  }
  if (!context.intake.answers.platform || context.intake.answers.platform === '还没想好') {
    return ['project_tech_lead', 'qa_testing', 'release_manager', 'documentation_delivery'].includes(agent.id);
  }
  return false;
}

function evidenceFor(agent, context, reasons) {
  const evidence = [];
  if (context.intake.mode === 'new_project') {
    if (context.intake.answers.idea) evidence.push({ source: 'intake.answers.idea', detail: '用户提供了项目描述。' });
    if (context.intake.answers.features) evidence.push({ source: 'intake.answers.features', detail: '用户提供了希望实现的能力。' });
    if (context.intake.answers.platform) evidence.push({ source: 'intake.answers.platform', detail: `用户选择：${context.intake.answers.platform}` });
  } else if (context.intake.answers.requestedChange) {
    evidence.push({ source: 'intake.answers.requestedChange', detail: '用户描述了本次希望发生的变化。' });
  }
  if (context.inspection.project.languages.length > 0) {
    evidence.push({ source: 'inspect.project.languages', detail: context.inspection.project.languages.join('、') });
  }
  if (context.inspection.project.platforms.length > 0) {
    evidence.push({ source: 'inspect.project.platforms', detail: context.inspection.project.platforms.join('、') });
  }
  if (context.inventory.configFiles.length > 0) {
    evidence.push({ source: `file:${context.inventory.configFiles[0]}`, detail: '检测到真实工程配置。' });
  }
  if (context.inventory.testFiles.length > 0 && ['qa_testing', 'project_tech_lead', 'release_manager'].includes(agent.id)) {
    evidence.push({ source: `file:${context.inventory.testFiles[0]}`, detail: '检测到现有测试。' });
  }
  if (context.impactFiles.length > 0 && context.intake.mode === 'existing_project') {
    evidence.push({ source: `file:${context.impactFiles[0].path}`, detail: '文件名或内容与用户改动描述有直接匹配。' });
  }
  for (const reason of reasons.filter((item) => item.startsWith('signal:'))) {
    evidence.push({ source: `derived:${reason.slice(7)}`, detail: '仅由用户描述中的明确词语触发。' });
  }
  return dedupeEvidence(evidence).slice(0, 8);
}

function analyzeAgent(agent, context, reasons) {
  const scope = requestSummary(context);
  const findings = [];
  const decisions = [];
  const protections = [];
  const tasks = [];

  if (agent.id === 'founder_decision') {
    findings.push(`当前规划基线是：${scope}`);
    decisions.push('只围绕用户已经表达的想法和能力形成第一阶段，不自动扩大产品。');
  } else if (agent.id === 'product_manager') {
    findings.push(context.intake.mode === 'new_project'
      ? `第一版闭环应先覆盖用户明确提出的能力：${context.intake.answers.features}`
      : `本次计划只围绕这次变化：${context.intake.answers.requestedChange}`);
    decisions.push('第一阶段只做一个可运行、可验证的小闭环。');
  } else if (agent.id === 'ui_ux') {
    findings.push('页面实现必须同时考虑加载、空内容、失败和成功反馈，具体页面不得凭空增加。');
    decisions.push('先基于用户描述确认最小入口与一次完整操作，再扩展页面。');
  } else if (agent.id === 'security_privacy') {
    findings.push('当前未被用户明确提出的数据、权限和第三方服务都不能视为已获授权。');
    protections.push('不得把密钥、验证码、私钥、凭证或敏感样例写入仓库。');
  } else if (agent.id === 'qa_testing') {
    findings.push(context.inventory.testFiles.length > 0
      ? `检测到 ${context.inventory.testFiles.length} 个测试相关文件，改动后必须运行现有测试。`
      : '未检测到现有测试文件，需要为第一阶段补充最小可重复验证。');
    tasks.push('为第一阶段主流程、失败状态和不受影响的既有能力建立最小验证。');
  } else if (agent.id === 'project_tech_lead') {
    findings.push(technicalFinding(context));
    decisions.push('按顺序执行最小任务，每一步完成后报告真实验证证据。');
  } else if (agent.id === 'release_manager') {
    findings.push('本次 plan 只形成开发计划，不代表构建、签名、审核或发布已经完成。');
    protections.push('没有真实构建和测试证据时，不得声称可以发布。');
  } else if (agent.id === 'documentation_delivery') {
    findings.push('交付给 Codex 的计划必须引用本次 run 的真实证据，并要求先总结再改代码。');
    tasks.push(`读取 ${publishedTaskPlanPath} 并先向项目主人复述目标、边界和第一阶段任务。`);
  } else {
    findings.push(`${agent.plainName}；该职责由 ${reasons.filter((item) => item.startsWith('signal:')).map((item) => item.slice(7)).join('、') || '当前工程证据'} 触发。`);
    tasks.push(...agent.inferredNeeds.slice(0, 2).map((need) => `在进入相关实现前整理并验证：${need}。`));
  }

  for (const rule of agent.codexRules || []) protections.push(rule);
  for (const documented of context.documentedProtections.slice(0, 4)) {
    protections.push(`保留已有约束（${documented.source}）：${documented.statement}`);
  }
  if (tasks.length === 0) tasks.push(`按“${agent.plainName}”的职责检查第一阶段计划，并留下可验证结果。`);

  return {
    summary: `${agent.name}已基于本次问答、只读扫描和项目文件完成规划分析。`,
    findings: unique(findings),
    decisions: unique(decisions),
    protections: unique(protections),
    tasks: unique(tasks)
  };
}

function technicalFinding(context) {
  const project = context.inspection.project;
  const facts = [
    project.platforms.length ? `平台 ${project.platforms.join('、')}` : '',
    project.languages.length ? `语言 ${project.languages.join('、')}` : '',
    project.buildSystems.length ? `构建方式 ${project.buildSystems.join('、')}` : ''
  ].filter(Boolean);
  if (facts.length > 0) return `只读扫描识别到${facts.join('；')}。`;
  return context.intake.mode === 'new_project'
    ? '当前没有源码工程，第一阶段只能建议建立最小可运行入口，不能声称源码已创建。'
    : '当前没有足够工程证据，不能凭空指定架构或受影响模块。';
}

function synthesizeTaskPlan(context, execution) {
  const impactAreas = taskImpactAreas(context);
  const protections = taskProtections(context, execution);
  const firstStage = firstStageTasks(context);
  const laterStages = laterStageTasks(context);
  const testChecks = testChecksFor(context);
  const releaseChecks = releaseChecksFor(context);
  const blockers = context.blockingQuestions.length > 0
    ? context.blockingQuestions
    : ['当前没有会阻止第一阶段开始的问题。'];
  const plan = {
    schemaVersion: runtimeSchemaVersion,
    runId: execution.runId,
    mode: context.intake.mode,
    request: requestSummary(context),
    understanding: understandingSummary(context),
    impactAreas,
    protections,
    firstStage,
    laterStages,
    testChecks,
    releaseChecks,
    blockingQuestions: context.blockingQuestions,
    codexInstructions: [
      '先总结项目目标、第一阶段边界、保护项、阻塞问题和下一步最小任务。',
      '在项目主人确认前，不要修改代码。',
      '不要实现用户没有明确提出的能力。'
    ]
  };
  return { json: plan, markdown: renderTaskPlan(plan) };
}

function taskImpactAreas(context) {
  if (context.intake.mode === 'existing_project') {
    if (context.impactFiles.length > 0) {
      return context.impactFiles.map((file) => `${file.path}（匹配：${file.matches.join('、')}）`);
    }
    const structural = [
      ...context.inventory.sourceFiles.slice(0, 5),
      ...context.inventory.configFiles.slice(0, 3)
    ];
    return structural.length > 0
      ? structural.map((file) => `${file}（仅作为现有工程入口候选，需读取后确认）`)
      : ['没有足够源码或配置证据定位影响区域，不能凭空指定文件。'];
  }
  if (context.intake.answers.platform === 'iPhone') return ['iPhone App 的最小工程入口和第一个可操作页面。'];
  if (context.intake.answers.platform === 'Mac') return ['macOS App 的最小工程入口和第一个可操作窗口。'];
  if (context.intake.answers.platform === '网页') return ['网页的最小工程入口和第一个可操作页面；不预先指定框架。'];
  return ['使用方式尚未确定，暂不创建特定平台的源码工程。'];
}

function taskProtections(context, execution) {
  const protections = [
    '只读取用户源码；plan 不能修改业务代码。',
    '不覆盖用户手写的 product 或 proof 文档。',
    '不加入用户没有提出的账号、收费、订阅、云服务或第三方工具。'
  ];
  if (context.inventory.testFiles.length > 0) protections.push('保留并运行现有测试。');
  if (context.inspection.project.buildSystems.length > 0) {
    protections.push(`保持现有构建方式可用：${context.inspection.project.buildSystems.join('、')}。`);
  }
  for (const item of context.documentedProtections) {
    protections.push(`已有资料 ${item.source}：${item.statement}`);
  }
  for (const item of execution.agents.flatMap((agent) => agent.protections)) protections.push(item);
  return unique(protections).slice(0, 20);
}

function firstStageTasks(context) {
  if (context.blockingQuestions.length > 0) {
    return ['先解决“真正阻止开发的问题”中的缺口，再建立源码任务。'];
  }
  if (context.intake.mode === 'existing_project') {
    return [
      '先读取用户描述、现有资料、相关源码和测试，确认直接影响区域。',
      '只修改与本次变化直接相关的最小文件集合。',
      '运行现有测试，并为本次变化补充一个最小回归验证。'
    ];
  }
  if (context.intake.answers.platform === 'iPhone') {
    return [
      '确认当前目录是否已有 Xcode 工程；没有时创建一个只面向 iPhone 的最小可运行工程。',
      '只实现一个承载用户首要操作的最小首页骨架。',
      '运行构建并验证一次最小操作，确认后再继续。'
    ];
  }
  if (context.intake.answers.platform === 'Mac') {
    return [
      '确认当前目录是否已有 macOS 工程；没有时创建一个只面向 macOS 的最小可运行工程。',
      '只实现一个承载用户首要操作的最小窗口骨架。',
      '运行 macOS 构建并验证一次最小操作，确认后再继续。'
    ];
  }
  if (context.intake.answers.platform === '网页') {
    return [
      '确认当前目录是否已有网页工程；没有时先选择与现有目录相容的最小工程形式，不预先指定框架。',
      '只实现一个承载用户首要操作的最小页面骨架。',
      '本地启动并验证一次最小操作，确认后再继续。'
    ];
  }
  return ['先确认使用方式，再建立对应的最小可运行工程。'];
}

function laterStageTasks(context) {
  return [
    '第一阶段经项目主人确认后，再补齐必要的加载、空内容、失败和成功状态。',
    '只有用户明确提出且证据充分时，才增加数据、权限、第三方服务或发布能力。',
    context.intake.mode === 'existing_project'
      ? '完成最小回归后，再评估是否需要扩大到相邻模块。'
      : '最小闭环可用后，再按用户反馈决定下一项能力。'
  ];
}

function testChecksFor(context) {
  const checks = [];
  if (context.inventory.testFiles.length > 0) {
    checks.push(`运行现有测试：${context.inventory.testFiles.slice(0, 4).join('、')}。`);
  } else {
    checks.push('为第一阶段最小操作、失败状态和输入边界补充可重复验证。');
  }
  checks.push('验证没有修改与本次计划无关的用户文件。');
  checks.push('记录真实执行的构建和测试命令，不把未验证内容写成已通过。');
  return checks;
}

function releaseChecksFor(context) {
  const checks = ['本次 plan 不执行发布，也不代表项目已经可以上线。'];
  if (context.intake.answers?.platform === 'iPhone' || context.signals.iphone) {
    checks.push('发布前再验证版本、真机、签名、隐私说明和分发材料。');
  } else if (context.intake.answers?.platform === 'Mac') {
    checks.push('发布前再验证版本、签名、公证、Gatekeeper 和分发包。');
  } else if (context.intake.answers?.platform === '网页') {
    checks.push('发布前再确认部署环境、隐私说明、监控和回滚方式。');
  } else {
    checks.push('使用方式确定后，再采用对应的构建和发布检查。');
  }
  return checks;
}

function renderTaskPlan(plan) {
  const section = (title, items) => [title, '', ...items.map((item) => `- ${item}`), ''];
  return [
    '# Jumao Agent Plan',
    '',
    ...section('## 1. 用户想做什么或这次想改什么', [plan.request]),
    ...section('## 2. Jumao 对需求的理解', [plan.understanding]),
    ...section('## 3. Agent 自动识别的影响区域', plan.impactAreas),
    ...section('## 4. 需要保护的已有功能', plan.protections),
    ...section('## 5. 第一阶段最小开发任务', plan.firstStage),
    ...section('## 6. 后续阶段', plan.laterStages),
    ...section('## 7. 测试检查', plan.testChecks),
    ...section('## 8. 发布检查', plan.releaseChecks),
    ...section('## 9. 真正阻止开发的问题', plan.blockingQuestions.length ? plan.blockingQuestions : ['没有。']),
    ...section('## 10. 给 Codex 的开始方式', plan.codexInstructions)
  ].join('\n').trimEnd() + '\n';
}

function writeRunArtifacts(runPath, context, execution, taskPlan) {
  for (const agent of execution.agents) {
    writeJSONAtomic(path.join(runPath, 'agents', `${agent.agentId}.json`), agent);
  }
  for (const group of execution.groups) {
    writeJSONAtomic(path.join(runPath, 'groups', `${group.groupId}.json`), group);
  }
  writeJSONAtomic(path.join(runPath, 'task-plan.json'), taskPlan.json);
  writeTextAtomic(path.join(runPath, 'planning-summary.md'), renderPlanningSummary(context, execution));
  writeJSONAtomic(path.join(runPath, 'manifest.json'), buildManifest(context, execution));
}

function writeFailureArtifacts(runPath, context, execution) {
  ensureRunDirectories(runPath);
  for (const agent of execution.agents) {
    writeJSONAtomic(path.join(runPath, 'agents', `${agent.agentId}.json`), agent);
  }
  for (const group of execution.groups) {
    writeJSONAtomic(path.join(runPath, 'groups', `${group.groupId}.json`), group);
  }
  writeTextAtomic(path.join(runPath, 'planning-summary.md'), renderPlanningSummary(context, execution));
  writeJSONAtomic(path.join(runPath, 'manifest.json'), buildManifest(context, execution));
}

function publishTaskPlan(workspacePath, runPath, markdown) {
  const destination = path.join(workspacePath, publishedTaskPlanPath);
  if (fs.existsSync(destination)) {
    const stat = fs.statSync(destination);
    if (!stat.isFile()) throw new Error(`${publishedTaskPlanPath} 不是普通文件，无法安全更新`);
    writeTextAtomic(path.join(runPath, 'previous-task-plan.md'), fs.readFileSync(destination, 'utf8'));
  }
  writeTextAtomic(destination, markdown);
}

function writeLatestRun(workspacePath, context, execution, runRelativePath) {
  writeJSONAtomic(path.join(workspacePath, latestRunPath), {
    schemaVersion: runtimeSchemaVersion,
    runId: execution.runId,
    runPath: runRelativePath,
    state: execution.state,
    inputFingerprint: context.inputFingerprint,
    startedAt: execution.startedAt,
    completedAt: execution.completedAt,
    counts: execution.counts,
    blockingQuestions: unique(execution.agents.flatMap((agent) => agent.blockingQuestions)),
    taskPlan: publishedTaskPlanPath
  });
}

function buildManifest(context, execution) {
  return {
    schemaVersion: runtimeSchemaVersion,
    runId: execution.runId,
    state: execution.state,
    executionMode: 'sequential',
    startedAt: execution.startedAt,
    completedAt: execution.completedAt,
    durationMs: durationBetween(execution.startedAt, execution.completedAt),
    inputFingerprint: context.inputFingerprint,
    input: {
      intake: intakePath,
      intakeState: context.intake.state,
      mode: context.intake.mode,
      inspectSchemaVersion: context.inspection.schemaVersion,
      workspaceKind: context.inspection.workspaceKind
    },
    counts: execution.counts,
    blockingQuestions: unique(execution.agents.flatMap((agent) => agent.blockingQuestions)),
    agents: execution.agents.map((agent) => ({
      agentId: agent.agentId,
      groupId: agent.groupId,
      status: agent.status,
      output: `agents/${agent.agentId}.json`
    })),
    groups: execution.groups.map((group) => ({
      groupId: group.groupId,
      sequence: group.sequence,
      counts: group.counts,
      output: `groups/${group.groupId}.json`
    })),
    artifacts: {
      planningSummary: 'planning-summary.md',
      taskPlan: 'task-plan.json',
      publishedTaskPlan: publishedTaskPlanPath
    },
    error: execution.error || null
  };
}

function renderPlanningSummary(context, execution) {
  return [
    '# Jumao Agent Planning Run',
    '',
    `- Run ID: ${execution.runId}`,
    `- 执行方式：8 个小组按注册表顺序依次执行`,
    `- 状态：${execution.state}`,
    `- completed: ${execution.counts.completed}`,
    `- skipped: ${execution.counts.skipped}`,
    `- blocked: ${execution.counts.blocked}`,
    `- failed: ${execution.counts.failed}`,
    '',
    '## 需求基线',
    requestSummary(context),
    '',
    '## 小组结果',
    ...execution.groups.map((group) => `- ${group.sequence}. ${group.groupName}: completed ${group.counts.completed}, skipped ${group.counts.skipped}, blocked ${group.counts.blocked}, failed ${group.counts.failed}`),
    '',
    ...(execution.error ? ['## 运行错误', execution.error, ''] : [])
  ].join('\n');
}

function executionAfterFailure(context, execution, failure) {
  const existing = new Map((execution?.agents || []).map((agent) => [agent.agentId, agent]));
  const agents = responsibilityAgents.map((agent) => {
    if (agent.id === 'documentation_delivery') {
      return {
        agentId: agent.id,
        groupId: agent.groupId,
        status: 'failed',
        summary: '写入 Agent 计划产物时发生真实错误。',
        evidence: [{ source: 'runtime:write', detail: '运行已进入产物写入阶段。' }],
        findings: [],
        decisions: [],
        protections: [],
        tasks: [],
        blockingQuestions: [],
        skippedReason: null,
        error: failure.message
      };
    }
    return existing.get(agent.id) || {
      agentId: agent.id,
      groupId: agent.groupId,
      status: 'skipped',
      summary: '',
      evidence: [],
      findings: [],
      decisions: [],
      protections: [],
      tasks: [],
      blockingQuestions: [],
      skippedReason: '运行在该 Agent 执行前失败。',
      error: null
    };
  });
  const existingGroups = new Map((execution?.groups || []).map((group) => [group.groupId, group]));
  const groups = agentGroups.map((group, index) => {
    const groupAgents = agents.filter((agent) => agent.groupId === group.id);
    const previous = existingGroups.get(group.id);
    const failureFinding = group.id === 'product_design'
      ? [`运行写入失败：${failure.message}`]
      : [];
    return {
      ...(previous || {}),
      groupId: group.id,
      groupName: group.name,
      sequence: index + 1,
      executionMode: 'sequential',
      dependsOnGroupId: index === 0 ? null : agentGroups[index - 1].id,
      startedAt: failure.startedAt,
      completedAt: failure.completedAt,
      durationMs: 0,
      participatingAgents: groupAgents.filter((agent) => agent.status !== 'skipped').map((agent) => agent.agentId),
      agentStatuses: groupAgents.map((agent) => ({ agentId: agent.agentId, status: agent.status })),
      counts: countAgentStatuses(groupAgents),
      mainFindings: unique([...(previous?.mainFindings || []), ...failureFinding]),
      boundaries: previous?.boundaries || [],
      protections: previous?.protections || [],
      receivedContext: previous?.receivedContext || null,
      handoff: {
        ...(previous?.handoff || {}),
        fromGroupId: group.id,
        findings: unique([...(previous?.handoff?.findings || []), ...failureFinding]),
        protections: previous?.handoff?.protections || [],
        tasks: previous?.handoff?.tasks || [],
        blockingQuestions: previous?.handoff?.blockingQuestions || []
      }
    };
  });
  return {
    schemaVersion: runtimeSchemaVersion,
    runId: failure.runId,
    startedAt: failure.startedAt,
    completedAt: failure.completedAt,
    executionMode: 'sequential',
    agents,
    groups,
    counts: countAgentStatuses(agents),
    state: 'blocked',
    error: failure.message
  };
}

function reusableResult(workspacePath, fingerprint) {
  const latestPath = path.join(workspacePath, latestRunPath);
  if (!fs.existsSync(latestPath) || !fs.existsSync(path.join(workspacePath, publishedTaskPlanPath))) return null;
  try {
    const latest = JSON.parse(fs.readFileSync(latestPath, 'utf8'));
    if (latest.inputFingerprint !== fingerprint) return null;
    const manifestPath = path.join(workspacePath, latest.runPath, 'manifest.json');
    if (!fs.existsSync(manifestPath)) return null;
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    return {
      ok: manifest.counts.failed === 0,
      state: manifest.state,
      runId: manifest.runId,
      runPath: latest.runPath,
      reused: true,
      counts: manifest.counts,
      artifacts: {
        manifest: path.posix.join(latest.runPath, 'manifest.json'),
        planningSummary: path.posix.join(latest.runPath, 'planning-summary.md'),
        taskPlan: publishedTaskPlanPath
      },
      blockingQuestions: latest.blockingQuestions || manifest.blockingQuestions || []
    };
  } catch {
    return null;
  }
}

function inputFingerprint(context) {
  const stable = {
    intake: {
      state: context.intake.state,
      schemaVersion: context.intake.schemaVersion || null,
      mode: context.intake.mode,
      answers: context.intake.answers,
      error: context.intake.error || null
    },
    inspect: {
      workspaceKind: normalizedWorkspaceKind(context.inspection.workspaceKind),
      project: context.inspection.project,
      evidence: context.inspection.evidence.filter((item) => item.kind !== 'jumao_file' && item.kind !== 'workspace_kind')
    },
    files: context.inventory.files.map((file) => ({
      path: file.path,
      kind: file.kind,
      size: file.size,
      contentHash: file.contentHash
    }))
  };
  return hashText(JSON.stringify(stable));
}

function normalizedWorkspaceKind(kind) {
  return ['empty', 'new'].includes(kind) ? 'new' : kind;
}

function statusRun(execution, runRelativePath) {
  return {
    runId: execution.runId,
    startedAt: execution.startedAt,
    completedAt: execution.completedAt,
    totalAgents: responsibilityAgents.length,
    completedAgents: execution.counts.completed,
    skippedAgents: execution.counts.skipped,
    blockedAgents: execution.counts.blocked,
    failedAgents: execution.counts.failed,
    groups: execution.groups,
    runPath: runRelativePath,
    blockingQuestions: unique(execution.agents.flatMap((agent) => agent.blockingQuestions)),
    error: execution.error || null
  };
}

function resultFromExecution(execution, runRelativePath, reused, error = null) {
  return {
    ok: execution.counts.failed === 0 && !error,
    state: execution.state,
    runId: execution.runId,
    runPath: runRelativePath,
    reused,
    counts: execution.counts,
    artifacts: {
      manifest: path.posix.join(runRelativePath, 'manifest.json'),
      planningSummary: path.posix.join(runRelativePath, 'planning-summary.md'),
      taskPlan: publishedTaskPlanPath
    },
    blockingQuestions: unique(execution.agents.flatMap((agent) => agent.blockingQuestions)),
    ...(error ? { error } : {})
  };
}

function finalState(counts) {
  return counts.blocked > 0 || counts.failed > 0 ? 'blocked' : 'ready';
}

function countAgentStatuses(agents) {
  const counts = { completed: 0, skipped: 0, blocked: 0, failed: 0 };
  for (const agent of agents) {
    if (!validAgentStatuses.has(agent.status)) throw new Error(`Unknown Agent status: ${agent.status}`);
    counts[agent.status] += 1;
  }
  return counts;
}

function requestSummary(context) {
  if (context.intake.state !== 'valid') return '首轮需求尚不可用。';
  if (context.intake.mode === 'existing_project') return context.intake.answers.requestedChange || '本次变化尚未说明。';
  return [context.intake.answers.idea, context.intake.answers.features].filter(Boolean).join('；') || '项目想法尚未说明。';
}

function understandingSummary(context) {
  if (context.intake.mode === 'existing_project') {
    return `先在现有项目中定位与“${context.intake.answers.requestedChange || '待确认'}”直接相关的代码和测试，只做最小变更。`;
  }
  const platform = context.intake.answers.platform === 'iPhone'
    ? '先在 iPhone 上使用'
    : context.intake.answers.platform === 'Mac'
      ? '先在 Mac 上使用'
      : context.intake.answers.platform === '网页'
        ? '先通过网页使用'
        : '使用方式暂未确定';
  return `用户想做“${context.intake.answers.idea || '待确认'}”，第一阶段先支持“${context.intake.answers.features || '待确认'}”，${platform}。`;
}

function searchTokens(text) {
  const ascii = String(text || '').toLowerCase().match(/[a-z0-9_\-]{3,}/g) || [];
  const chineseSegments = String(text || '').match(/[\u4e00-\u9fff]{2,8}/g) || [];
  const chinese = chineseSegments.flatMap((segment) => {
    const tokens = [segment];
    for (let index = 0; index < segment.length - 1; index += 1) {
      tokens.push(segment.slice(index, index + 2));
    }
    return tokens;
  });
  const stop = new Set(['一个', '可以', '希望', '用户', '现在', '这个', '那个', '进行', '能够', '需要']);
  return unique([...ascii, ...chinese]).filter((item) => !stop.has(item)).slice(0, 30);
}

function skippedAgent(base, reason) {
  return { ...base, status: 'skipped', skippedReason: reason };
}

function ensureRunDirectories(runPath) {
  fs.mkdirSync(path.join(runPath, 'agents'), { recursive: true });
  fs.mkdirSync(path.join(runPath, 'groups'), { recursive: true });
}

function writeJSONAtomic(file, value) {
  writeTextAtomic(file, `${JSON.stringify(value, null, 2)}\n`);
}

function writeTextAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomUUID()}`;
  try {
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
  } catch (error) {
    try { fs.rmSync(temporary, { force: true }); } catch {}
    throw error;
  }
}

function makeRunId(startedAt, options) {
  const stamp = startedAt.replace(/[-:.TZ]/g, '').slice(0, 17);
  const suffix = options.runIdSuffix || crypto.randomUUID().slice(0, 8);
  return `${stamp}-${suffix}`;
}

function nowISO(options = {}) {
  if (typeof options.now === 'function') return new Date(options.now()).toISOString();
  return new Date().toISOString();
}

function durationBetween(startedAt, completedAt) {
  const value = new Date(completedAt).getTime() - new Date(startedAt).getTime();
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function hashText(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function isReadableDirectory(directory) {
  try {
    return fs.statSync(directory).isDirectory();
  } catch {
    return false;
  }
}

function textValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function listValue(value) {
  return Array.isArray(value) ? value.map(textValue).filter(Boolean).join('、') : textValue(value);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function dedupeEvidence(items) {
  const seen = new Set();
  return items.filter((item) => {
    const key = `${item.source}\u0000${item.detail}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function safeErrorMessage(error) {
  if (error instanceof Error && error.message) return error.message;
  return String(error || 'Unknown planning error');
}

function failedResult(error, extra = {}) {
  return {
    ok: false,
    state: 'blocked',
    reused: false,
    error,
    ...extra
  };
}
