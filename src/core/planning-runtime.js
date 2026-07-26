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
const platformPendingDecision = '准备开始写平台相关代码前，需要确认先做 iPhone、Mac 还是网页';
const validAgentStatuses = new Set(['completed', 'skipped', 'blocked', 'failed']);
const validImpactTypes = new Set([
  'created_task', 'removed_risk', 'protected_constraint', 'changed_priority', 'merged_task'
]);
const priorityImpactAgentIds = new Set([
  'security_privacy', 'privacy_request_ops', 'medical_claims_review', 'algorithm_validation_evidence',
  'qa_testing', 'release_manager'
]);
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

const signalPatterns = {
  iphone: /iphone|ios|苹果手机/,
  mac: /macos|mac app|mac 应用|mac 工具/,
  web: /网页|网站|web(?:site| app)?|browser/,
  watch: /watch|手表|心率/,
  login: /登录|登陆|login|sign[ -]?in|account|账号|账户|注册/,
  payment: /支付|付费|收费|订阅|会员|购买|退款|payment|subscription|purchase|membership/,
  cloud: /云|同步|换机|服务端|后端|服务器|cloud|sync|backend/,
  health: /健康|医疗|诊断|治疗|睡眠|心率|血压|health|medical/,
  sensitive: /身份证|手机号|定位|通讯录|隐私|敏感|儿童|照片|privacy|location|contact/,
  china: /中国大陆|大陆用户|备案|微信|短信|china/,
  release: /发布|上架|app store|testflight|提审|上线|release/,
  analytics: /统计|分析|留存|转化|analytics/,
  messaging: /微信|短信|验证码|wechat|sms/,
  algorithm: /算法|评分|预测|推荐|报告|趋势|algorithm|score|predict/,
  company: /公司|企业|商业化|融资|company|business/,
  brand: /品牌|商标|图标|名称|brand|trademark/,
  publicUsers: /公开|外部用户|真实用户|客户|朋友|public users?|customers?/,
  thirdParty: /第三方|供应商|sdk|外包|vendor/,
  abuse: /防刷|滥用|验证码|公开入口|abuse/,
  support: /客服|退款|注销|反馈|support/,
  anonymous: /匿名|anonymous/,
  localOnly: /本地假数据|本地模拟|仅使用本地|local fake|mock data|local-only/
};

const platformAgentRequirements = {
  ios_engineer: 'apple',
  watchos_engineer: 'watch',
  website_frontend: 'web',
  app_store_submission: 'apple',
  iap_revenue_ops: 'apple'
};

const platformRequirementLabels = {
  apple: 'Apple 平台',
  watch: 'watchOS',
  web: 'Web 平台'
};

const roleEvidencePatterns = {
  website_frontend: /html|css|jsx|tsx|vue|svelte|web|网页|catalog|页面/,
  backend_engineer: /auth|login|account|session|user|member|subscription|登录|账号|账户|会员|匿名/,
  admin_dashboard_product: /admin|support|account|refund|客服|后台|账号|退款/,
  cicd_build: /\.github\/workflows|ci|build|deploy|package\.json|makefile|project\.yml/,
  database_engineer: /database|schema|model|account|user|member|subscription|数据库|字段|账号|会员/,
  security_privacy: /privacy|security|password|credential|account|payment|隐私|安全|密码|凭证|账号|支付/,
  data_governance_dictionary: /data|schema|account|user|member|subscription|数据|字段|账号|会员/,
  privacy_request_ops: /delete|account|user|privacy|注销|删除|账号|隐私/,
  legal_compliance: /privacy|terms|payment|subscription|release|隐私|协议|支付|订阅|发布/,
  finance_tax: /payment|subscription|purchase|refund|支付|订阅|购买|退款/,
  support_operations: /support|refund|delete|account|客服|退款|注销|账号/,
  iap_revenue_ops: /storekit|iap|subscription|purchase|订阅|内购|购买/,
  qa_testing: /test|spec|xctest|pytest|测试/,
  release_manager: /release|publish|sign|notary|deploy|发布|提审|签名|公证/,
  sre_stability: /monitor|alert|incident|deploy|监控|告警|事故|部署/,
  remote_config_gray_release: /feature flag|remote config|rollout|gray|灰度|功能开关/,
  device_lab_test_data: /device|fixture|test data|真机|设备|测试数据/
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
      if (reused) {
        emitPlanningEvent(options, planningEvent('run.started', {
          runId: reused.runId,
          timestamp: nowISO(options),
          counts: emptyAgentCounts(),
          reused: true,
          groups: registeredGroupSummaries()
        }));
        emitPlanningEvent(options, planningEvent('run.completed', {
          runId: reused.runId,
          timestamp: nowISO(options),
          counts: reused.counts,
          state: reused.state,
          reused: true,
          runPath: reused.runPath
        }));
        return reused;
      }
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
      blockingQuestions: [],
      platformPending: context.platformPending,
      pendingDecision: context.pendingDecision
    });
    checkingWritten = true;

    emitPlanningEvent(options, planningEvent('run.started', {
      runId,
      timestamp: startedAt,
      counts: emptyAgentCounts(),
      reused: false,
      groups: registeredGroupSummaries()
    }));

    execution = executePipeline(context, {
      runId,
      startedAt,
      now: options.now,
      onEvent: options.onEvent
    });
    const completedAt = nowISO(options);
    execution.completedAt = completedAt;
    execution.counts = countAgentStatuses(execution.agents);
    execution.state = finalState(context, execution.counts);

    const taskPlan = synthesizeTaskPlan(context, execution);
    writeRunArtifacts(runPath, context, execution, taskPlan);
    publishTaskPlan(workspacePath, runPath, taskPlan.markdown);
    writeLatestRun(workspacePath, context, execution, runRelativePath);
    writePlanningStatus(workspacePath, execution.state, statusRun(execution, runRelativePath));

    emitPlanningEvent(options, planningEvent('run.completed', {
      runId,
      timestamp: completedAt,
      counts: execution.counts,
      state: execution.state,
      reused: false,
      runPath: runRelativePath
    }));

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
        const failedAgent = failedExecution.agents.find((agent) => agent.status === 'failed');
        if (failedAgent) {
          const failedGroup = failedExecution.groups.find((group) => group.groupId === failedAgent.groupId);
          emitPlanningEvent(options, planningEvent('agent.failed', {
            runId,
            timestamp: failedExecution.completedAt,
            groupId: failedAgent.groupId,
            groupName: failedGroup?.groupName,
            agentId: failedAgent.agentId,
            agentName: agentName(failedAgent.agentId),
            agentStatus: failedAgent.status,
            counts: failedExecution.counts,
            groupCounts: failedGroup?.counts,
            summary: failedAgent.summary,
            error: failedAgent.error || message
          }));
        }
        emitPlanningEvent(options, planningEvent('run.failed', {
          runId,
          timestamp: failedExecution.completedAt,
          counts: failedExecution.counts,
          state: failedExecution.state,
          reused: false,
          runPath: runRelativePath,
          error: message
        }));
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
    emitPlanningEvent(options, planningEvent('run.failed', {
      runId,
      timestamp: nowISO(options),
      counts: execution?.counts || emptyAgentCounts(),
      state: 'blocked',
      reused: false,
      runPath: runRelativePath,
      error: message
    }));
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
  const detected = detectSignals(answerText, intake, inspection);
  const impactFiles = findImpactFiles(inventory, answerText);
  const documentedProtections = findDocumentedProtections(inventory);
  const scope = scopeForRequest(answerText);
  const evidenceGate = evidenceGateFor(answerText, documentedProtections, detected, scope);
  const executionBoundary = executionBoundaryFor(answerText, detected, scope);
  const explicitGoals = explicitGoalsFor(answerText, detected);
  const blockingQuestions = unique([...blockingQuestionsFor(intake), ...evidenceGate.questions]);
  const platformPending = intake.state === 'valid'
    && intake.mode === 'new_project'
    && (!intake.answers.platform || intake.answers.platform === '还没想好');
  return {
    workspacePath,
    intake,
    inspection,
    inventory,
    signals: detected.signals,
    negativeSignals: detected.negativeSignals,
    signalEvidence: detected.signalEvidence,
    platforms: detected.platforms,
    impactFiles,
    documentedProtections,
    scope,
    evidenceGate,
    executionBoundary,
    explicitGoals,
    blockingQuestions,
    platformPending,
    pendingDecision: platformPending ? platformPendingDecision : null
  };
}

function detectSignals(answerText, intake, inspection) {
  const value = answerText.toLowerCase();
  const platform = intake.mode === 'new_project' ? intake.answers.platform : '';
  const project = inspection.project || {};
  const signals = {};
  const negativeSignals = [];
  const signalEvidence = {};
  for (const [name, pattern] of Object.entries(signalPatterns)) {
    const mentions = classifySignalMentions(value, pattern);
    signals[name] = mentions.positive;
    signalEvidence[name] = mentions;
    if (mentions.negative) negativeSignals.push(name);
  }

  signals.iphone ||= platform === 'iPhone' || (project.platforms || []).includes('iOS');
  signals.mac ||= platform === 'Mac' || (project.platforms || []).includes('macOS');
  signals.web ||= platform === '网页' || (project.platforms || []).includes('Web');

  const knownPlatforms = project.platforms || [];
  const inferredPlatforms = [
    ...(signals.web && !knownPlatforms.includes('Node CLI') ? ['Web'] : []),
    ...(signals.iphone && (knownPlatforms.length === 0 || knownPlatforms.some((item) => ['iOS', 'macOS', 'watchOS'].includes(item))) ? ['iOS'] : []),
    ...(signals.mac && (knownPlatforms.length === 0 || knownPlatforms.some((item) => ['iOS', 'macOS', 'watchOS'].includes(item))) ? ['macOS'] : []),
    ...(signals.watch && (knownPlatforms.length === 0 || knownPlatforms.some((item) => ['iOS', 'macOS', 'watchOS'].includes(item))) ? ['watchOS'] : [])
  ];
  let platforms = unique([...(project.platforms || []), ...inferredPlatforms]);
  if (signals.web && !signals.cloud) platforms = platforms.filter((item) => item !== 'Backend');
  return { signals, negativeSignals: unique(negativeSignals), signalEvidence, platforms };
}

function classifySignalMentions(value, pattern) {
  const matcher = new RegExp(pattern.source, 'gi');
  const matches = [...value.matchAll(matcher)];
  let positive = false;
  let negative = false;
  for (const match of matches) {
    if (mentionIsNegated(value, match.index || 0)) negative = true;
    else positive = true;
  }
  return {
    positive,
    negative,
    matches: matches.map((match) => match[0])
  };
}

function mentionIsNegated(value, index) {
  const prefix = value.slice(Math.max(0, index - 32), index);
  const boundaries = /[，。；,.;!?]|但是|不过|然而|但|\b(?:but|however)\b/gi;
  let clauseStart = 0;
  for (const match of prefix.matchAll(boundaries)) clauseStart = (match.index || 0) + match[0].length;
  const clause = prefix.slice(clauseStart);
  return /(?:不|不要|暂不|禁止|无需|无须|避免|未|不会|不能|不得)[^，。；;,.!?]{0,12}$/i.test(clause)
    || /(?:do not|don't|not|no|without|never|won't|will not)\s+(?:\w+\s+){0,4}$/i.test(clause);
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
      protections.push({ source: `${file.path}:${index + 1}`, statement: trimmed, scope: scopeForPath(file.path) });
    });
  }
  return protections.slice(0, 20);
}

function scopeForRequest(answerText) {
  const packages = [...answerText.matchAll(/packages\/([a-z0-9._-]+)/gi)]
    .map((match) => `packages/${match[1]}/**`);
  return { paths: packages.length > 0 ? unique(packages) : ['**'] };
}

function scopeForPath(filePath) {
  const match = filePath.match(/^(packages\/[^/]+)\//);
  return { paths: match ? [`${match[1]}/**`] : ['**'] };
}

function scopesOverlap(left, right) {
  const leftPaths = left?.paths || ['**'];
  const rightPaths = right?.paths || ['**'];
  return leftPaths.includes('**') || rightPaths.includes('**')
    || leftPaths.some((item) => rightPaths.includes(item));
}

function executionBoundaryFor(answerText, detected, scope) {
  const value = answerText.toLowerCase();
  const irreversible = /迁移|migration|认证.{0,12}(?:切换|替换)|权限.{0,12}(?:收紧|提升)|不可逆|(?:删除|覆盖).{0,20}(?:真实用户|生产|全部数据)/.test(value);
  const realHealthData = detected.signals.health && /healthkit|健康数据|health data/.test(value);
  const productionEffect = irreversible || realHealthData
    || /生产数据库|真实支付|生产发布|发布生产|production database|real payment|production release/.test(value);
  const executeReason = irreversible
    ? '真实生产迁移、认证切换或不可逆数据操作必须在当前会话中再次获得明确授权。'
    : realHealthData
      ? '读取或上传真实用户健康数据必须在当前会话中再次获得明确授权。'
      : '真实账号、真实数据、生产环境和外部付费服务操作必须在当前会话中再次获得明确授权。';
  return {
    scope,
    irreversible,
    realHealthData,
    phases: [
      { phase: 'prepare', status: 'authorized', reason: '允许在当前明确范围内编写代码、配置、脚本、备份和回滚方案。' },
      { phase: 'validate', status: 'authorized', reason: '允许在本地、测试环境或隔离 worktree 中运行测试和模拟验证。' },
      { phase: 'execute', status: 'blocked', reason: executeReason }
    ],
    productionEffect
  };
}

function explicitGoalsFor(answerText, detected) {
  const value = answerText.toLowerCase();
  const goals = [];
  const add = (goalId, label, taskPattern) => {
    if (!goals.some((goal) => goal.goalId === goalId)) goals.push({ goalId, label, taskPattern });
  };
  const membership = /会员|订阅|membership|subscription/.test(value);
  const login = /登录|登陆|login|sign[ -]?in/.test(value);
  const anonymous = /匿名|访客|anonymous|guest/.test(value);
  const healthData = /healthkit|健康数据|health data/.test(value);
  const migration = /迁移|migration/.test(value);

  if (detected.signals.web && login) add('goal:web-entry', '网页登录入口', /网页.{0,12}入口|入口.{0,12}网页|页面.{0,12}登录/);
  if (anonymous) add('goal:anonymous-browsing', '匿名或访客浏览', /匿名|访客|anonymous|guest/);
  if (login) add('goal:login-flow', '登录流程', /登录|login|sign[ -]?in/);
  if (membership) {
    add('goal:membership-state', '会员状态', /会员状态|membership state|会员/);
    add('goal:membership-entitlement', '会员权益行为', /会员.{0,12}权益|权益.{0,12}会员|membership.{0,12}entitlement|entitlement/);
  }
  if (detected.platforms.includes('Node CLI') && /--json|json 输出/.test(value)) {
    add('goal:cli-json', 'CLI JSON 输出', /--json|json 输出/);
  }
  if (detected.platforms.includes('Node CLI') && /保留.{0,16}文本输出|文本输出.{0,16}兼容|human-readable|text output/.test(value)) {
    add('goal:cli-text-compatibility', 'CLI 文本输出兼容', /文本输出|human-readable|text output/);
  }
  if (healthData) {
    add('goal:health-authorization', 'HealthKit 最小授权', /HealthKit.{0,16}授权|授权.{0,16}HealthKit/i);
    add('goal:health-refusal', '健康授权拒绝状态', /授权拒绝|拒绝授权|denied|refusal/);
  }
  if (/删除本地|删除.{0,12}健康数据|delete local/.test(value)) {
    add('goal:health-local-deletion', '本地健康数据删除', /删除.{0,16}本地健康|删除本地健康|本地健康.{0,16}删除/);
  }
  if (/不提供诊断|不诊断|不预测疾病|non-diagnostic|not.{0,12}diagnos/.test(value)) {
    add('goal:health-non-diagnostic', '非诊断边界', /非诊断|不提供诊断|不得.{0,8}诊断|non-diagnostic/);
  }
  if (/报名|signup|sign-up/.test(value) && /草稿|draft/.test(value)) {
    add('goal:signup-draft', '活动报名草稿', /活动报名草稿|报名.{0,8}草稿|signup.{0,8}draft/);
  }
  if (migration) {
    add('goal:migration-backup', '迁移备份', /备份|backup/);
    add('goal:migration-script', '迁移脚本', /迁移脚本|migration script/);
    add('goal:migration-rollback', '迁移回滚', /回滚|rollback/);
    add('goal:migration-validation', '测试数据迁移验证', /测试数据|模拟数据|dry[- ]?run|迁移.{0,12}测试|测试.{0,12}迁移/);
  }
  return goals;
}

function evidenceGateFor(answerText, documentedProtections, detected, scope) {
  const value = answerText.toLowerCase();
  const blockers = [];
  const has = (pattern) => pattern.test(value);
  const noChange = has(/(?:不需要|无需|不必).{0,16}(?:代码|计划|改动|变化)|\bno\s+(?:code|plan|changes?)\s+(?:are\s+)?(?:needed|required)\b/);
  const deferredLogin = has(/(?:以后|未来|later|future).{0,32}(?:login|登录|账号|账户)/)
    && has(/(?:当前|本次|now|current).{0,48}(?:不做|不要|不需要|without|no).{0,24}(?:login|登录|账号|账户|数据库)/);
  if (deferredLogin) {
    blockers.push({
      agents: new Set(signalAgentMap.login),
      question: '当前只提到未来可能的登录，但没有可执行的账号范围；请确认是否要在本次实现登录。'
    });
  }

  const anonymousRequired = documentedProtections.some((item) => scopesOverlap(item.scope, scope) && /(?:必须|must|保留|keep).{0,18}(?:匿名|anonymous)/i.test(item.statement));
  const mandatoryLogin = has(/(?:所有|all).{0,20}(?:访问|用户|visitors?|users?).{0,20}(?:必须|must).{0,12}(?:登录|login)/)
    || has(/(?:禁止|do not allow|no).{0,20}(?:匿名|anonymous)/);
  if (anonymousRequired && mandatoryLogin) {
    blockers.push({
      agents: new Set(signalAgentMap.login),
      question: '匿名访问约束与强制登录请求冲突；请由项目负责人确认哪条规则优先。'
    });
  }

  const bilingualReleaseAmbiguity = has(/(?:do not|don't).{0,28}release/)
    && has(/不要.{0,12}发布/)
    && has(/(?:keep|保留).{0,28}(?:beta\s+)?(?:release|发布)/);
  if (bilingualReleaseAmbiguity) {
    blockers.push({
      agents: new Set(signalAgentMap.release),
      question: '中英文发布否定语句的作用范围相互矛盾；请明确本阶段是否允许 beta 发布。'
    });
  }

  return {
    noChange,
    questions: unique(blockers.map((item) => item.question)),
    blocks(agent) {
      return blockers.some((item) => !item.agents || item.agents.has(agent.id));
    }
  };
}

function blockingQuestionsFor(intake) {
  if (intake.state === 'corrupt') return ['请重新完成首轮问答，当前答案文件无法读取。'];
  if (intake.state === 'missing') return ['请先在 Jumao Cat 或 jumao interview 中完成首轮问答。'];
  if (intake.mode === 'new_project') {
    const questions = [];
    if (!intake.answers.idea) questions.push('你想做个什么？');
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
    emitPlanningEvent(run, planningEvent('group.started', {
      runId: run.runId,
      timestamp: groupStartedAt,
      groupId: group.id,
      groupName: group.name,
      counts: countAgentStatuses(agents),
      groupCounts: emptyAgentCounts()
    }));

    const groupAgents = [];
    for (const agent of responsibilityAgents.filter((candidate) => candidate.groupId === group.id)) {
      const output = executeAgent(agent, context);
      groupAgents.push(output);
      agents.push(output);
      const eventName = `agent.${output.status}`;
      emitPlanningEvent(run, planningEvent(eventName, {
        runId: run.runId,
        timestamp: nowISO({ now: run.now }),
        groupId: group.id,
        groupName: group.name,
        agentId: agent.id,
        agentName: agent.name,
        agentStatus: output.status,
        counts: countAgentStatuses(agents),
        groupCounts: countAgentStatuses(groupAgents),
        summary: output.summary,
        skippedReason: output.skippedReason,
        error: output.error
      }));
    }
    const counts = countAgentStatuses(groupAgents);
    const findings = unique(groupAgents.flatMap((agent) => agent.findings)).slice(0, 12);
    const protections = unique(groupAgents.flatMap((agent) => agent.protections)).slice(0, 12);
    const tasks = unique(groupAgents.flatMap((agent) => agent.tasks)).slice(0, 12);
    const handoff = {
      fromGroupId: group.id,
      findings,
      protections,
      tasks,
      blockingQuestions: unique(groupAgents.flatMap((agent) => agent.blockingQuestions)),
      pendingDecision: context.pendingDecision
    };
    const groupResult = {
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
      handoff,
      platformPending: context.platformPending,
      pendingDecision: context.pendingDecision
    };
    groups.push(groupResult);
    emitPlanningEvent(run, planningEvent('group.completed', {
      runId: run.runId,
      timestamp: groupResult.completedAt,
      groupId: group.id,
      groupName: group.name,
      counts: countAgentStatuses(agents),
      groupCounts: counts,
      summary: findings[0] || '本组已完成当前项目适用性检查。'
    }));
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
    state: 'checking',
    platformPending: context.platformPending,
    pendingDecision: context.pendingDecision
  };
}

function emptyAgentCounts() {
  return { completed: 0, skipped: 0, blocked: 0, failed: 0 };
}

function registeredGroupSummaries() {
  return agentGroups.map((group) => ({
    groupId: group.id,
    groupName: group.name,
    totalAgents: responsibilityAgents.filter((agent) => agent.groupId === group.id).length
  }));
}

function agentName(id) {
  return responsibilityAgents.find((agent) => agent.id === id)?.name || id;
}

function planningEvent(event, details) {
  const counts = details.counts || emptyAgentCounts();
  return {
    schemaVersion: runtimeSchemaVersion,
    runId: details.runId || null,
    timestamp: details.timestamp,
    event,
    groupId: details.groupId || null,
    groupName: details.groupName || null,
    agentId: details.agentId || null,
    agentName: details.agentName || null,
    agentStatus: details.agentStatus || null,
    completedAgents: counts.completed,
    skippedAgents: counts.skipped,
    blockedAgents: counts.blocked,
    failedAgents: counts.failed,
    totalAgents: responsibilityAgents.length,
    groupCounts: details.groupCounts || null,
    summary: details.summary || null,
    skippedReason: details.skippedReason || null,
    state: details.state || null,
    reused: details.reused ?? false,
    runPath: details.runPath || null,
    error: details.error || null,
    groups: details.groups || null
  };
}

function emitPlanningEvent(options, event) {
  if (typeof options.onEvent === 'function') options.onEvent(event);
}

function executeAgent(agent, context) {
  const base = {
    agentId: agent.id,
    roleId: agent.id,
    groupId: agent.groupId,
    status: 'skipped',
    summary: '',
    triggerReasons: [],
    triggerReason: null,
    negativeSignals: context.negativeSignals || [],
    scope: context.scope || { paths: ['**'] },
    intentEvidence: [],
    projectEvidence: [],
    roleEvidence: [],
    evidence: [],
    evidenceQuality: { valid: false, validEvidence: [], invalidReasons: [] },
    findings: [],
    independentFinding: null,
    decisions: [],
    protections: [],
    protectedConstraint: null,
    tasks: [],
    assessmentOutcome: null,
    generatedTask: null,
    decisionImpact: null,
    changedPlanDecision: null,
    affectedTaskIds: [],
    impactType: null,
    unusedEvidence: false,
    blockingQuestions: [],
    planContribution: null,
    incompleteEvidence: false,
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

  const relevance = relevanceForAgent(agent, context);
  if (relevance.reasons.length === 0) {
    return skippedAgent(base, relevance.skippedReason);
  }

  const intentEvidence = intentEvidenceFor(context, relevance.reasons);
  const projectEvidence = projectEvidenceFor(context);
  const roleEvidence = roleEvidenceFor(agent, context);
  const evidence = dedupeEvidence([...intentEvidence, ...projectEvidence, ...roleEvidence]).slice(0, 12);

  if (context.evidenceGate.blocks(agent)) {
    return {
      ...base,
      status: 'blocked',
      summary: '证据门发现当前职责无法安全得出可执行结论。',
      triggerReasons: relevance.reasons,
      triggerReason: relevance.reasons.join('、'),
      intentEvidence,
      projectEvidence,
      roleEvidence,
      evidence,
      evidenceQuality: validateEvidenceQuality(evidence),
      blockingQuestions: context.evidenceGate.questions
    };
  }

  if (context.blockingQuestions.length > 0 && blocksAgent(agent, context)) {
    return {
      ...base,
      status: 'blocked',
      summary: '缺少会直接影响当前实现方向的信息，暂不能完成该职责判断。',
      triggerReasons: relevance.reasons,
      intentEvidence,
      projectEvidence,
      roleEvidence,
      evidence,
      blockingQuestions: context.blockingQuestions
    };
  }

  const analysis = context.evidenceGate.noChange || !agentNeedsPlanChange(agent, context, relevance)
    ? noChangeAnalysis(agent, context)
    : analyzeAgent(agent, context, relevance.reasons);
  const triggerReason = relevance.reasons.join('、');
  const evidenceQuality = validateEvidenceQuality(evidence);
  const independentFinding = analysis.findings[0] || null;
  const protectedConstraint = analysis.protections[0] || null;
  const generatedTask = analysis.tasks[0] || null;
  const assessmentOutcome = analysis.assessmentOutcome || (generatedTask || protectedConstraint ? 'changed_plan' : 'no_change');
  const decisionImpact = assessmentOutcome === 'changed_plan' ? decisionImpactFor(agent, analysis) : null;
  const planContribution = assessmentOutcome === 'changed_plan'
    ? planContributionFor(agent, analysis, evidence, relevance.reasons, decisionImpact, context.scope)
    : null;
  const contract = validateAgentEvidence({
    roleId: agent.id,
    triggerReason,
    evidenceQuality,
    independentFinding,
    assessmentOutcome,
    protectedConstraint,
    generatedTask,
    decisionImpact,
    planContribution
  });
  const result = {
    ...base,
    roleId: agent.id,
    triggerReason,
    summary: analysis.summary,
    triggerReasons: relevance.reasons,
    intentEvidence,
    projectEvidence,
    roleEvidence,
    evidenceQuality,
    evidence,
    findings: analysis.findings,
    independentFinding,
    decisions: analysis.decisions,
    protections: analysis.protections,
    protectedConstraint,
    tasks: analysis.tasks,
    assessmentOutcome,
    generatedTask,
    decisionImpact,
    changedPlanDecision: decisionImpact?.changedPlanDecision || null,
    affectedTaskIds: decisionImpact?.affectedTaskIds || [],
    impactType: decisionImpact?.impactType || null,
    unusedEvidence: contract.unusedEvidence,
    planContribution,
    incompleteEvidence: !contract.valid
  };
  if (!contract.valid) {
    return {
      ...result,
      status: 'skipped',
      planContribution: null,
      skippedReason: `证据契约不完整：${contract.issues.join('、')}`
    };
  }
  return { ...result, status: 'completed' };
}

function relevanceForAgent(agent, context) {
  const isNodeCLI = context.platforms.includes('Node CLI');
  if (isNodeCLI && ['ui_ux', 'website_frontend', 'design_system_qa', 'accessibility'].includes(agent.id)) {
    return { reasons: [], skippedReason: '当前项目是 Node CLI，没有页面或网页界面证据。' };
  }
  const reasons = [];
  if (alwaysRelevantAgentIds.has(agent.id)) reasons.push('runtime-baseline');
  for (const [signal, ids] of Object.entries(signalAgentMap)) {
    if (context.signals[signal] && ids.includes(agent.id)) reasons.push(`signal:${signal}`);
  }
  if (context.intake.mode === 'existing_project') {
    if (agent.id === 'cicd_build' && context.inventory.configFiles.length > 0) reasons.push('existing-config');
    if (agent.id === 'design_system_qa' && /界面|页面|ui|view/i.test(context.intake.answers.requestedChange)) reasons.push('existing-ui-change');
  }
  const requestText = Object.values(context.intake.answers || {}).filter((value) => typeof value === 'string').join('\n').toLowerCase();
  if (agent.id === 'privacy_request_ops' && /删除本地|delete local|删除.*数据/.test(requestText)) reasons.push('explicit-local-deletion');
  const uniqueReasons = unique(reasons);
  const requirement = platformAgentRequirements[agent.id];
  if (uniqueReasons.length > 0 && requirement && !platformRequirementSatisfied(requirement, context.platforms)) {
    return {
      reasons: [],
      skippedReason: `当前项目缺少${platformRequirementLabels[requirement]}证据，该职责与已确认平台不兼容。`
    };
  }
  if (uniqueReasons.length > 0) return { reasons: uniqueReasons, skippedReason: null };

  const excludedSignals = context.negativeSignals.filter((signal) => signalAgentMap[signal]?.includes(agent.id));
  if (excludedSignals.length > 0) {
    return {
      reasons: [],
      skippedReason: `用户明确排除了相关能力或阶段：${excludedSignals.map(plainSignalLabel).join('、')}。`
    };
  }
  return {
    reasons: [],
    skippedReason: '没有发现触发该职责的正向需求信号、平台条件或基线责任。'
  };
}

function agentNeedsPlanChange(agent, context, relevance) {
  const request = Object.values(context.intake.answers || {}).filter((value) => typeof value === 'string').join('\n').toLowerCase();
  const membership = /会员|订阅|membership|subscription/.test(request);
  const explicitDataModel = /字段|数据字典|database|schema|数据库/.test(request);
  const explicitSupport = /客服|退款|support|refund/.test(request);
  const explicitAdmin = /后台|admin|rbac|运营后台/.test(request);
  const explicitAccessibility = /无障碍|辅助功能|accessibility/.test(request);
  const paymentIntent = !context.negativeSignals.includes('payment')
    && (membership || /支付|收费|购买|payment|purchase/.test(request));
  if (['founder_decision', 'documentation_delivery', 'release_manager'].includes(agent.id)) return false;
  if (agent.id === 'project_tech_lead') return Boolean(context.executionBoundary.irreversible);
  if (agent.id === 'cicd_build') return relevance.reasons.some((reason) => reason.startsWith('signal:release'));
  if (agent.id === 'security_privacy') return ['login', 'health', 'sensitive'].some((signal) => context.signals[signal]);
  if (agent.id === 'qa_testing') return Boolean(requestSummary(context).trim());
  if (agent.id === 'product_manager') return Boolean(requestSummary(context).trim());
  if (agent.id === 'ui_ux') return context.platforms.some((platform) => ['Web', 'iOS', 'macOS'].includes(platform));
  if (['database_engineer', 'data_governance_dictionary'].includes(agent.id)) return membership || explicitDataModel;
  if (agent.id === 'privacy_request_ops') return /删除本地|delete local|删除.*数据|真实账号|生产登录/.test(request);
  if (agent.id === 'support_operations') return explicitSupport || paymentIntent;
  if (agent.id === 'admin_dashboard_product') return explicitAdmin;
  if (agent.id === 'accessibility') return explicitAccessibility;
  if (agent.id === 'finance_tax') return paymentIntent;
  return relevance.reasons.some((reason) => reason.startsWith('signal:'));
}

function platformRequirementSatisfied(requirement, platforms) {
  if (requirement === 'apple') return platforms.some((platform) => ['iOS', 'macOS', 'watchOS'].includes(platform));
  if (requirement === 'watch') return platforms.includes('watchOS');
  if (requirement === 'web') return platforms.includes('Web');
  return true;
}

function blocksAgent(agent, context) {
  if (context.intake.mode === 'existing_project') return !context.intake.answers.requestedChange;
  return !context.intake.answers.idea && alwaysRelevantAgentIds.has(agent.id);
}

function intentEvidenceFor(context, reasons) {
  const evidence = [];
  if (context.intake.mode === 'new_project') {
    if (context.intake.answers.idea) evidence.push({ source: 'intake.answers.idea', detail: '用户提供了项目描述。' });
    if (context.intake.answers.features) evidence.push({ source: 'intake.answers.features', detail: '用户提供了希望实现的能力。' });
    if (context.intake.answers.platform) evidence.push({ source: 'intake.answers.platform', detail: `用户选择：${context.intake.answers.platform}` });
  } else if (context.intake.answers.requestedChange) {
    evidence.push({ source: 'intake.answers.requestedChange', detail: '用户描述了本次希望发生的变化。' });
  }
  for (const reason of reasons.filter((item) => item.startsWith('signal:'))) {
    evidence.push({ source: `derived:${reason.slice(7)}`, detail: '由用户描述中的明确正向表达触发。' });
  }
  return dedupeEvidence(evidence).slice(0, 8);
}

function projectEvidenceFor(context) {
  const evidence = [];
  if (context.inspection.project.languages.length > 0) {
    evidence.push({ source: 'inspect.project.languages', detail: context.inspection.project.languages.join('、') });
  }
  if (context.platforms.length > 0) {
    evidence.push({ source: 'inspect.project.platforms', detail: context.platforms.join('、') });
  }
  if (context.inspection.project.buildSystems.length > 0) {
    evidence.push({ source: 'inspect.project.buildSystems', detail: context.inspection.project.buildSystems.join('、') });
  }
  return dedupeEvidence(evidence).slice(0, 8);
}

function roleEvidenceFor(agent, context) {
  const evidence = [];
  if (['qa_testing', 'project_tech_lead', 'release_manager'].includes(agent.id) && context.inventory.testFiles.length > 0) {
    evidence.push({ source: `file:${context.inventory.testFiles[0]}`, detail: '检测到与验证职责直接相关的现有测试。' });
  }
  if (agent.id === 'cicd_build') {
    const ciFile = context.inventory.files.find((file) => /(^|\/)\.github\/workflows\//.test(file.path));
    if (ciFile) evidence.push({ source: `file:${ciFile.path}`, detail: '检测到与 CI/CD 职责直接相关的工作流配置。' });
  }
  const pattern = roleEvidencePatterns[agent.id];
  if (pattern) {
    for (const file of context.inventory.files) {
      if (!['source', 'test', 'config', 'product', 'proof', 'document'].includes(file.kind)) continue;
      if (!pattern.test(`${file.path.toLowerCase()}\n${file.searchText}`)) continue;
      evidence.push({ source: `file:${file.path}`, detail: '文件名或内容与该角色职责直接相关。' });
      if (evidence.length >= 4) break;
    }
  }
  return dedupeEvidence(evidence).slice(0, 8);
}

const evidenceSourcePatterns = [
  /^intake\.answers\./,
  /^inspect\./,
  /^manifest\./,
  /^derived:/,
  /^file:/
];

export function validateEvidenceQuality(evidence = []) {
  const validEvidence = [];
  const invalidReasons = [];
  for (const item of Array.isArray(evidence) ? evidence : []) {
    if (!item || typeof item.source !== 'string' || typeof item.detail !== 'string') {
      invalidReasons.push('evidence 必须包含 source 和 detail');
      continue;
    }
    if (!evidenceSourcePatterns.some((pattern) => pattern.test(item.source))) {
      invalidReasons.push(`不支持的 evidence 来源：${item.source}`);
      continue;
    }
    if (item.detail.trim().length < 2) {
      invalidReasons.push(`evidence 描述过短：${item.source}`);
      continue;
    }
    validEvidence.push({ source: item.source, detail: item.detail });
  }
  const uniqueEvidence = dedupeEvidence(validEvidence);
  if (uniqueEvidence.length === 0) invalidReasons.push('没有有效 evidence');
  return {
    valid: invalidReasons.length === 0 && uniqueEvidence.length > 0,
    validEvidence: uniqueEvidence,
    invalidReasons: unique(invalidReasons)
  };
}

export function validateAgentEvidence({
  roleId,
  triggerReason,
  evidence,
  evidenceQuality,
  independentFinding,
  assessmentOutcome,
  protectedConstraint,
  generatedTask,
  decisionImpact,
  planContribution
} = {}) {
  const quality = evidenceQuality || validateEvidenceQuality(evidence);
  const issues = [];
  const outcome = assessmentOutcome || (meaningfulContractText(generatedTask) || meaningfulContractText(protectedConstraint) || hasPlanImpact(decisionImpact)
    ? 'changed_plan'
    : 'no_change');
  const noChange = outcome === 'no_change';
  const unusedEvidence = false;
  if (typeof roleId !== 'string' || roleId.trim().length === 0) issues.push('缺少 roleId');
  if (typeof triggerReason !== 'string' || triggerReason.trim().length === 0) issues.push('缺少 triggerReason');
  if (!quality.valid) issues.push(...quality.invalidReasons);
  if (!meaningfulContractText(independentFinding)) issues.push('缺少 independentFinding');
  if (!['changed_plan', 'no_change'].includes(outcome)) issues.push('assessmentOutcome 无效');
  if (noChange) {
    if (meaningfulContractText(protectedConstraint) || meaningfulContractText(generatedTask) || hasPlanImpact(decisionImpact) || planContribution) {
      issues.push('no_change 不得生成任务、约束、影响或贡献');
    }
  } else {
    if (!meaningfulContractText(protectedConstraint) && !meaningfulContractText(generatedTask)) {
      issues.push('缺少 protectedConstraint 或 generatedTask');
    }
    if (!hasPlanImpact(decisionImpact)) issues.push('缺少 decisionImpact');
    if (!planContribution || !Array.isArray(planContribution.agentIds) || !planContribution.agentIds.includes(roleId)) {
      issues.push('缺少 planContribution');
    }
  }
  return { valid: issues.length === 0, issues: unique(issues), evidenceQuality: quality, unusedEvidence };
}

export function validateGoalCoverage(goals = [], priorityTasks = [], blockingQuestions = []) {
  const coveredBy = new Map();
  for (const task of Array.isArray(priorityTasks) ? priorityTasks : []) {
    for (const goalId of Array.isArray(task.goalIds) ? task.goalIds : []) {
      const taskIds = coveredBy.get(goalId) || [];
      taskIds.push(task.taskId);
      coveredBy.set(goalId, unique(taskIds));
    }
  }
  const result = (Array.isArray(goals) ? goals : []).map((goal) => {
    const taskIds = coveredBy.get(goal.goalId) || [];
    if (taskIds.length > 0) return { goalId: goal.goalId, label: goal.label, status: 'covered', taskIds, blockingReason: null };
    const blockingReason = blockingQuestions[0] || null;
    return {
      goalId: goal.goalId,
      label: goal.label,
      status: blockingReason ? 'blocked' : 'missing',
      taskIds: [],
      blockingReason
    };
  });
  return {
    valid: result.every((goal) => goal.status === 'covered' || goal.status === 'blocked'),
    goals: result
  };
}

function meaningfulContractText(value) {
  return typeof value === 'string' && value.trim().length >= 8;
}

function planContributionFor(agent, analysis, evidence = [], triggerReasons = [], decisionImpact = null, scope = { paths: ['**'] }) {
  return {
    agentIds: [agent.id],
    sections: contributionSectionsFor(agent),
    tasks: analysis.tasks,
    protections: analysis.protections,
    blockingQuestions: [],
    triggerReasons,
    triggerReason: triggerReasons.join('、'),
    evidence,
    independentFinding: analysis.findings[0] || null,
    protectedConstraint: analysis.protections[0] || null,
    generatedTask: analysis.tasks[0] || null,
    decisionImpact,
    scope
  };
}

function noChangeAnalysis(agent, context) {
  const finding = agent.id === 'project_tech_lead'
    ? technicalFinding(context)
    : `已检查“${requestSummary(context)}”，当前证据没有显示 ${agent.plainName} 需要新增任务、约束或优先级变化。`;
  return {
    summary: `${agent.name}已完成评估，现有计划足够。`,
    findings: [finding],
    decisions: unique([
      '保持现有计划，不生成额外开发任务。',
      context.platformPending && ['project_tech_lead', 'qa_testing', 'release_manager', 'documentation_delivery'].includes(agent.id)
        ? context.pendingDecision
        : null
    ].filter(Boolean)),
    protections: [],
    tasks: [],
    assessmentOutcome: 'no_change'
  };
}

function decisionImpactFor(agent, analysis) {
  const generatedTask = analysis.tasks[0] || null;
  const protectedConstraint = analysis.protections[0] || null;
  if (generatedTask) {
    const changedPriority = priorityImpactAgentIds.has(agent.id);
    return {
      changedPlanDecision: changedPriority
        ? `将 ${agent.name} 发现的风险任务提升为 high 优先级。`
        : `将 ${agent.name} 的可执行任务加入计划优先任务池。`,
      affectedTaskIds: [taskIdFor(generatedTask)],
      impactType: changedPriority ? 'changed_priority' : 'created_task',
      lowContribution: false
    };
  }
  if (protectedConstraint) {
    return {
      changedPlanDecision: `将 ${agent.name} 的保护约束加入计划边界。`,
      affectedTaskIds: [],
      impactType: 'protected_constraint',
      lowContribution: false
    };
  }
  return {
    changedPlanDecision: '',
    affectedTaskIds: [],
    impactType: null,
    lowContribution: true
  };
}

function hasPlanImpact(decisionImpact) {
  if (!decisionImpact || typeof decisionImpact !== 'object') return false;
  if (!validImpactTypes.has(decisionImpact.impactType)) return false;
  if (typeof decisionImpact.changedPlanDecision !== 'string' || decisionImpact.changedPlanDecision.trim().length < 8) return false;
  if (!Array.isArray(decisionImpact.affectedTaskIds)) return false;
  if (['created_task', 'changed_priority', 'merged_task'].includes(decisionImpact.impactType)) {
    return decisionImpact.affectedTaskIds.length > 0;
  }
  return true;
}

function taskIdFor(task) {
  return `task-${hashText(contractTextKey(task)).slice(0, 12)}`;
}

function contributionSectionsFor(agent) {
  if (['finance_tax', 'support_operations', 'iap_revenue_ops', 'app_store_submission', 'sre_stability', 'remote_config_gray_release', 'device_lab_test_data'].includes(agent.id)) {
    return ['laterStages', 'protections'];
  }
  if (agent.id === 'release_manager') return ['releaseChecks', 'protections'];
  if (agent.id === 'qa_testing') return ['firstStage', 'testChecks', 'protections'];
  return ['firstStage', 'protections'];
}

function analyzeAgent(agent, context, reasons) {
  const scope = requestSummary(context);
  const findings = [];
  const decisions = [];
  const protections = [];
  const tasks = [];
  const request = Object.values(context.intake.answers || {}).filter((value) => typeof value === 'string').join('\n').toLowerCase();
  const requestsMembership = /会员|订阅|membership|subscription/.test(request);
  const requestsCLIJSON = context.platforms.includes('Node CLI') && /--json|json 输出/.test(request);
  const requestsHealthKit = /healthkit|健康数据|健康趋势|health data|health trend/.test(request);
  const requestsLocalDeletion = /删除本地|delete local|删除.*数据/.test(request);
  const requestsNonDiagnostic = /不提供诊断|不诊断|non-diagnostic|not.*diagnos|不预测疾病/.test(request);
  const requestsSignupDraft = /报名|signup|sign-up|草稿|draft/.test(request);

  if (agent.id === 'founder_decision') {
    findings.push(`当前规划基线是：${scope}`);
    decisions.push('只围绕用户已经表达的想法和能力形成第一阶段，不自动扩大产品。');
    tasks.push('核对第一阶段任务是否都能追溯到用户描述，删除没有证据的新能力。');
  } else if (agent.id === 'product_manager') {
    findings.push(context.intake.mode === 'new_project'
      ? (context.intake.answers.features
          ? `第一版先把“${context.intake.answers.features}”整理成一次能完成的使用过程。`
          : '用户尚未补充具体使用动作；先从项目描述整理最小过程，不编造新能力。')
      : '本次计划只处理用户描述的变化，不自动扩大到相邻功能。');
    decisions.push('第一阶段只做一个可运行、可验证的小闭环。');
    tasks.push(requestsCLIJSON
      ? '为现有 CLI 增加 --json 输出，并保留原有人类可读文本输出作为兼容行为。'
      : requestsSignupDraft
        ? '实现登录后的活动报名草稿，保留访客查看活动，并明确草稿的可见结果。'
      : '把用户描述整理成一次能完成的使用过程，并为每一步写明可见结果。');
  } else if (agent.id === 'ui_ux') {
    findings.push('页面实现必须同时考虑加载、空内容、失败和成功反馈，具体页面不得凭空增加。');
    decisions.push('先基于用户描述确认最小入口与一次完整操作，再扩展页面。');
    tasks.push('列出第一阶段入口、主要操作以及加载、空内容、失败和成功状态。');
  } else if (agent.id === 'website_frontend') {
    findings.push('当前需求和项目证据指向 Web 使用方式，网页任务不得混入 Apple 平台实现。');
    tasks.push(requestsMembership
      ? '实现或验证网页入口、匿名浏览入口以及登录后状态和会员权益的最小界面变化。'
      : '实现或验证网页入口、匿名浏览入口以及登录后状态的最小界面变化。');
  } else if (agent.id === 'backend_engineer') {
    findings.push(requestsMembership
      ? '登录与会员状态需要明确区分匿名、已登录和会员三种状态，但第一阶段不自动扩大成生产后端。'
      : '登录需求只要求匿名与已登录状态；没有会员、订阅或生产后端证据。');
    let task = requestsMembership
      ? '定义匿名、已登录和会员状态及权益行为，保留匿名浏览作为可回归行为。'
      : '定义匿名与已登录状态，保留匿名浏览，并实现本次明确的核心操作。';
    if (context.signals.localOnly || context.negativeSignals.includes('payment')) {
      decisions.push('第一阶段仅使用本地假账号状态，不连接真实支付。');
      task += requestsMembership
        ? ' 使用本地假账号和假会员状态验证流程，不保存真实密码或支付信息。'
        : ' 使用本地假账号验证流程，不保存真实密码或支付信息。';
    }
    tasks.push(task);
  } else if (agent.id === 'cicd_build') {
    const workflows = context.inventory.files.filter((file) => /(^|\/)\.github\/workflows\//.test(file.path));
    findings.push(workflows.length > 0
      ? `检测到 ${workflows.length} 个 CI 工作流，改动后应继续运行现有自动检查。`
      : '检测到现有构建配置，但没有足够证据要求新增发布证书或签名流程。');
    tasks.push('保留现有构建和测试命令，并记录本次真实运行结果。');
  } else if (agent.id === 'database_engineer') {
    findings.push('本地账号状态只需要最小数据边界；没有生产数据库证据。');
    tasks.push('定义本地账号状态的数据边界，标明字段用途、保存位置、删除条件和假数据范围。');
    if (context.signals.localOnly) protections.push('第一阶段不得创建生产数据库或保存真实账号数据。');
  } else if (agent.id === 'security_privacy') {
    findings.push('当前未被用户明确提出的数据、权限和第三方服务都不能视为已获授权。');
    protections.push('不得把密钥、验证码、私钥、凭证或敏感样例写入仓库。');
    tasks.push('只记录第一阶段实际涉及的数据和权限；没有用户证据的服务保持未启用。');
  } else if (agent.id === 'data_governance_dictionary') {
    findings.push('本地账号状态只需要最小数据边界；没有生产数据库证据。');
    tasks.push('定义本地账号状态的数据边界，标明字段用途、保存位置、删除条件和假数据范围。');
  } else if (agent.id === 'privacy_request_ops') {
    if (requestsLocalDeletion) {
      findings.push('用户明确要求删除本地健康数据，删除范围和结果必须可验证。');
      tasks.push('实现并验证本地健康趋势数据删除，不保留删除后的副本。');
    } else {
      findings.push('如果后续启用真实账号，必须先定义注销和删除流程；本地假账号阶段不声称已具备生产能力。');
      tasks.push('把真实账号注销和数据删除列为进入生产登录前的后续阶段条件。');
    }
  } else if (agent.id === 'finance_tax') {
    findings.push('订阅规划需要先明确会员权益；没有真实支付时，不应产生收款、税务或对账已就绪的结论。');
    tasks.push('明确会员权益和未来收费边界，把真实支付与收入对账留到后续阶段。');
  } else if (agent.id === 'support_operations') {
    findings.push('真实登录和收费前需要退款、注销与反馈流程；当前可以先定义边界，不启用生产运营。');
    tasks.push('把退款、注销和账号反馈流程列为真实登录与支付前的后续阶段条件。');
  } else if (agent.id === 'iap_revenue_ops') {
    findings.push('当前 Apple 平台证据与订阅意图同时成立，才需要评估 IAP 商品和会员权益。');
    tasks.push('在 Apple 平台范围内定义 IAP 商品、会员权益和恢复购买规则。');
  } else if (agent.id === 'qa_testing') {
    findings.push(context.inventory.testFiles.length > 0
      ? `检测到 ${context.inventory.testFiles.length} 个测试相关文件，改动后必须运行现有测试。`
      : '未检测到现有测试文件，需要为第一阶段补充最小可重复验证。');
    tasks.push(requestsCLIJSON
      ? '验证 --json 输出与原有人类可读文本输出都保持兼容，并运行现有 CLI 测试。'
      : '为第一阶段主流程、失败状态和不受影响的既有能力建立最小验证。');
  } else if (agent.id === 'project_tech_lead') {
    findings.push(technicalFinding(context));
    decisions.push('按顺序执行最小任务，每一步完成后报告真实验证证据。');
    tasks.push('按第一阶段任务顺序逐项执行，每完成一步就记录实际文件和验证命令。');
  } else if (agent.id === 'release_manager') {
    findings.push('本次 plan 只形成开发计划，不代表构建、签名、审核或发布已经完成。');
    protections.push('没有真实构建和测试证据时，不得声称可以发布。');
    tasks.push('保留发布前检查清单；只有真实构建和测试完成后才更新结论。');
  } else if (agent.id === 'documentation_delivery') {
    findings.push('交付给 Codex 的计划必须引用本次 run 的真实证据，并明确 prepare、validate 与 execute 的授权边界。');
    tasks.push(`读取 ${publishedTaskPlanPath}，总结目标、边界和第一阶段任务，然后在当前授权范围内继续 prepare 与 validate。`);
  } else if (agent.id === 'health_content' && requestsHealthKit) {
    findings.push('健康趋势需要最小 HealthKit 授权、授权拒绝状态和本地数据删除边界。');
    tasks.push('实现最小 HealthKit 授权请求、授权拒绝状态、本地模拟健康数据和删除本地健康趋势数据的操作；不得读取或上传真实健康数据。');
  } else if (agent.id === 'medical_claims_review' && requestsNonDiagnostic) {
    findings.push('用户明确要求非诊断边界，趋势展示不能表述为诊断、治疗或疾病预测。');
    protections.push('健康趋势不得声称诊断、治疗或预测疾病。');
    tasks.push('在健康趋势界面和验证中明确非诊断边界。');
  } else {
    findings.push(`${agent.plainName}；${plainTriggerReason(reasons)}。`);
    tasks.push(...agent.inferredNeeds.slice(0, 2).map((need) => `在进入相关实现前整理并验证：${need}。`));
  }

  if (context.executionBoundary.irreversible) {
    if (agent.id === 'project_tech_lead') {
      tasks.unshift('prepare：设计迁移方案并实现备份、迁移脚本和回滚；validate：在测试数据或 dry-run 上验证；execute：真实生产迁移保持 blocked。');
    } else if (agent.id === 'qa_testing') {
      tasks.unshift('validate：使用隔离测试数据运行备份、迁移和回滚验证；不得连接或修改真实生产数据。');
    }
  }
  if (context.executionBoundary.realHealthData && agent.id === 'qa_testing') {
    tasks.unshift('validate：使用本地模拟健康数据验证授权、拒绝、删除和非诊断边界；不得读取真实用户健康数据。');
  }

  if (context.platformPending && ['project_tech_lead', 'qa_testing', 'release_manager', 'documentation_delivery'].includes(agent.id)) {
    decisions.push(context.pendingDecision);
  }
  if (agent.id !== 'release_manager') {
    for (const rule of agent.codexRules || []) protections.push(rule);
  }
  for (const documented of context.documentedProtections.filter((item) => scopesOverlap(item.scope, context.scope)).slice(0, 4)) {
    protections.push(`保留已有约束（${documented.source}）：${documented.statement}`);
  }
  if (tasks.length === 0) tasks.push(`按“${agent.plainName}”的职责检查第一阶段计划，并留下可验证结果。`);

  return {
    summary: `${agent.name}已基于本次问答、只读扫描和项目文件完成规划分析。`,
    findings: unique(findings),
    decisions: unique(decisions),
    protections: conciseProtections(protections),
    tasks: unique(tasks)
  };
}

function technicalFinding(context) {
  const project = context.inspection.project;
  const facts = [
    context.platforms.length ? `平台 ${context.platforms.join('、')}` : '',
    project.languages.length ? `语言 ${project.languages.join('、')}` : '',
    project.buildSystems.length ? `构建方式 ${project.buildSystems.join('、')}` : ''
  ].filter(Boolean);
  if (facts.length > 0) return `只读扫描识别到${facts.join('；')}。`;
  return context.intake.mode === 'new_project'
    ? '当前没有源码工程，第一阶段只能建议建立最小可运行入口，不能声称源码已创建。'
    : '当前没有足够工程证据，不能凭空指定架构或受影响模块。';
}

function plainTriggerReason(reasons) {
  const labels = {
    iphone: '用户明确选择 iPhone',
    web: '用户明确选择网页',
    watch: '用户明确提到手表或相关设备',
    login: '用户明确提到账号或登录',
    payment: '用户明确提到收费、购买或订阅',
    cloud: '用户明确提到同步、云端或服务端',
    health: '用户明确提到健康或医疗内容',
    sensitive: '用户明确提到敏感数据或权限',
    china: '用户明确提到中国大陆相关服务',
    release: '用户明确提到发布或上架',
    analytics: '用户明确提到统计或分析',
    messaging: '用户明确提到短信或微信',
    algorithm: '用户明确提到算法、预测或评分',
    company: '用户明确提到公司或商业用途',
    brand: '用户明确提到品牌或商标',
    publicUsers: '用户明确提到面向其他用户开放',
    thirdParty: '用户明确提到第三方服务',
    abuse: '用户明确提到滥用防护',
    support: '用户明确提到客服或用户反馈'
  };
  const triggers = reasons
    .filter((item) => item.startsWith('signal:'))
    .map((item) => labels[item.slice(7)] || '用户描述提供了直接证据');
  return unique(triggers).join('、') || '现有工程文件提供了直接证据';
}

function plainSignalLabel(signal) {
  const labels = {
    login: '登录或账号',
    payment: '真实支付或收费',
    cloud: '云端或服务端',
    release: '发布或上架',
    publicUsers: '面向外部用户',
    messaging: '短信或微信',
    health: '健康或医疗能力'
  };
  return labels[signal] || signal;
}

function conciseProtections(items) {
  const seen = new Set();
  return unique(items).filter((item) => {
    let key = item;
    const documented = item.match(/^(?:已有资料 |保留已有约束（)([^）]+?)(?:）)?：(.+)$/i);
    if (documented) key = `documented:${documented[1].toLowerCase()}:${documented[2].toLowerCase()}`;
    if (/(密钥|私钥|凭证|验证码|敏感样例).*(仓库|写进|写入)/.test(item)) key = 'protect-secrets';
    else if (/(不得声称|不代表).*(发布|提审|上线)|可以发布/.test(item)) key = 'require-release-proof';
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function synthesizeTaskPlan(context, execution) {
  const impactAreas = taskImpactAreas(context);
  const protections = taskProtections(context, execution);
  const contributions = context.evidenceGate.questions.length > 0 ? [] : collectPlanContributions(execution);
  const firstStage = firstStageTasks(context, contributions);
  const laterStages = laterStageTasks(context, contributions);
  const priorityTasks = priorityTaskRecords(contributions, ['firstStage', 'laterStages'], context.explicitGoals);
  const goalCoverageResult = validateGoalCoverage(context.explicitGoals, priorityTasks, context.blockingQuestions);
  const goalCoverageQuestions = goalCoverageResult.valid
    ? []
    : goalCoverageResult.goals
      .filter((goal) => goal.status === 'missing')
      .map((goal) => `明确目标“${goal.label}”（${goal.goalId}）没有被 priorityTask 覆盖，不能安全交给 Codex。`);
  const handoffBlockingQuestions = unique([...context.blockingQuestions, ...goalCoverageQuestions]);
  const testChecks = testChecksFor(context);
  const releaseChecks = releaseChecksFor(context);
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
    priorityTasks,
    testChecks,
    releaseChecks,
    contributions,
    blockingQuestions: handoffBlockingQuestions,
    goalCoverage: goalCoverageResult.goals,
    handoffReady: goalCoverageResult.valid && context.blockingQuestions.length === 0,
    executionBoundaries: context.executionBoundary.phases,
    platformPending: context.platformPending,
    pendingDecision: context.pendingDecision,
    codexInstructions: [
      '先总结项目目标、第一阶段边界、保护项、阻塞问题和下一步最小任务。',
      '当前执行请求已授权本次明确范围内的 prepare 和 validate；不需要为了普通本地代码修改再次索要主人确认。',
      'execute 阶段涉及真实账号、真实数据、生产环境或外部付费服务时仍然 blocked；不要因 execute 未授权而停止 prepare 或 validate。',
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
  if (context.negativeSignals.includes('release')) protections.push('用户明确要求本阶段不发布、不提审、不部署生产环境。');
  if (context.negativeSignals.includes('payment')) protections.push('用户明确要求本阶段不连接真实支付或打开真实收费。');
  if (context.signals.localOnly) protections.push('第一阶段仅使用本地假数据，不保存真实账号或支付信息。');
  for (const item of context.documentedProtections.filter((item) => scopesOverlap(item.scope, context.scope))) {
    protections.push(`已有资料 ${item.source}：${item.statement}`);
  }
  for (const item of execution.agents.flatMap((agent) => agent.protections)) protections.push(item);
  return conciseProtections(protections).slice(0, 20);
}

function collectPlanContributions(execution) {
  return execution.agents
    .filter((agent) => agent.status === 'completed' && agent.planContribution)
    .map((agent) => ({
      agentIds: agent.planContribution.agentIds,
      agentNames: agent.planContribution.agentIds.map(agentName),
      sections: agent.planContribution.sections,
      tasks: agent.planContribution.tasks,
      protections: agent.planContribution.protections,
      blockingQuestions: agent.planContribution.blockingQuestions,
      independentFinding: agent.independentFinding,
      protectedConstraint: agent.protectedConstraint,
      generatedTask: agent.generatedTask,
      decisionImpact: agent.decisionImpact,
      triggerReasons: agent.triggerReasons,
      triggerReason: agent.triggerReason,
      evidence: agent.evidence,
      evidenceSources: agent.evidence.map((item) => item.source),
      scope: agent.scope
    }));
}

function firstStageTasks(context, contributions) {
  if (context.blockingQuestions.length > 0) {
    return ['先解决“真正阻止开发的问题”中的缺口，再建立源码任务。'];
  }
  const contributionTasks = prioritizedContributionTasks(contributions, 'firstStage');
  if (context.intake.mode === 'existing_project') {
    const directFiles = context.impactFiles.slice(0, 3).map((file) => file.path);
    const files = directFiles.length > 0
      ? directFiles
      : unique([...context.inventory.sourceFiles.slice(0, 3), ...context.inventory.configFiles.slice(0, 1)]);
    const matchedTests = context.impactFiles.filter((file) => file.kind === 'test').map((file) => file.path);
    const tests = matchedTests.length > 0 ? matchedTests.slice(0, 3) : context.inventory.testFiles.slice(0, 3);
    return unique([
      files.length > 0
        ? (directFiles.length > 0
            ? `先读取与本次变化直接匹配的文件：${files.join('、')}。`
            : `先读取现有工程入口候选并确认影响范围：${files.join('、')}。`)
        : '先读取用户描述、现有资料、相关源码和测试，确认直接影响区域。',
      ...contributionTasks,
      '只修改与本次变化直接相关的最小文件集合。',
      tests.length > 0
        ? `运行现有测试并补充最小回归验证，优先检查：${tests.join('、')}。`
        : '为本次变化补充一个最小可重复验证。'
    ]);
  }
  if (context.intake.answers.platform === 'iPhone') {
    return unique([
      '确认当前目录是否已有 Xcode 工程；没有时创建一个只面向 iPhone 的最小可运行工程。',
      ...contributionTasks,
      '只实现一个承载用户首要操作的最小首页骨架。',
      '运行构建并验证一次最小操作，确认后再继续。'
    ]);
  }
  if (context.intake.answers.platform === 'Mac') {
    return unique([
      '确认当前目录是否已有 macOS 工程；没有时创建一个只面向 macOS 的最小可运行工程。',
      ...contributionTasks,
      '只实现一个承载用户首要操作的最小窗口骨架。',
      '运行 macOS 构建并验证一次最小操作，确认后再继续。'
    ]);
  }
  if (context.intake.answers.platform === '网页') {
    return unique([
      '确认当前目录是否已有网页工程；没有时先选择与现有目录相容的最小工程形式，不预先指定框架。',
      ...contributionTasks,
      '只实现一个承载用户首要操作的最小页面骨架。',
      '本地启动并验证一次最小操作，确认后再继续。'
    ]);
  }
  return unique([
    context.intake.answers.features
      ? '把上面确认的第一版能力整理成一次完整的用户操作过程和必要页面状态。'
      : '从项目描述整理一次完整的用户操作过程和必要页面状态，不补写用户没有提出的能力。',
    ...contributionTasks,
    '只整理需要保存的数据、隐私边界和可验证结果，不引入账号、收费、订阅、云服务或第三方工具。',
    '准备与使用方式无关的目录、说明和测试清单，暂不创建任何特定平台的源码工程。',
    platformPendingDecision
  ]);
}

function laterStageTasks(context, contributions) {
  const contributionTasks = prioritizedContributionTasks(contributions, 'laterStages');
  return unique([
    '第一阶段 prepare 和 validate 完成后，再补齐必要的加载、空内容、失败和成功状态。',
    ...contributionTasks,
    '只有用户明确提出且证据充分时，才增加数据、权限、第三方服务或发布能力。',
    context.intake.mode === 'existing_project'
      ? '完成最小回归后，再评估是否需要扩大到相邻模块。'
      : '最小闭环可用后，再按用户反馈决定下一项能力。'
  ]);
}

function prioritizedContributionTasks(contributions, section) {
  return priorityTaskRecords(contributions, [section]).map((record) => {
    const evidence = record.evidence.find((item) => item.source.startsWith('file:'))
      || record.evidence.find((item) => item.source.startsWith('derived:'))
      || record.evidence[0];
    const trigger = record.triggerReason ? `；触发：${record.triggerReason}` : '';
    return `${record.task}（来源：${record.contributingRoles.map(agentName).join('、')}${evidence ? `；依据：${evidence.source}` : ''}${trigger}）`;
  });
}

export function priorityTaskRecords(contributions = [], sections = [], goals = []) {
  const priority = [
    'backend_engineer', 'website_frontend', 'database_engineer', 'security_privacy',
    'data_governance_dictionary', 'privacy_request_ops', 'product_manager', 'ui_ux',
    'health_content', 'medical_claims_review', 'ios_engineer', 'finance_tax', 'support_operations',
    'iap_revenue_ops', 'qa_testing', 'project_tech_lead'
  ];
  const records = [];
  for (const item of contributions
    .filter((item) => sections.some((section) => item.sections.includes(section)))
    .sort((left, right) => {
      const leftIndex = priority.indexOf(left.agentIds[0]);
      const rightIndex = priority.indexOf(right.agentIds[0]);
      return (leftIndex < 0 ? priority.length : leftIndex) - (rightIndex < 0 ? priority.length : rightIndex);
    })) {
    const task = item.tasks.find((candidate) => !/按第一阶段任务顺序|读取 tasks\/jumao-agent-plan\.md|核对第一阶段任务/.test(candidate));
    if (!task) continue;
    const taskKey = contractTextKey(task);
    const findingKey = contractTextKey(item.independentFinding);
    const scope = item.scope || { paths: ['**'] };
    const goalIds = goalIdsForTask(task, goals);
    const existing = records.find((record) => JSON.stringify(record.scope) === JSON.stringify(scope)
      && (record.taskKey === taskKey || (findingKey && record.findingKeys.includes(findingKey))));
    if (existing) {
      const roleId = item.agentIds[0];
      if (existing.contributingRoles.includes(roleId)) continue;
      const originalImpact = item.decisionImpact || {
        changedPlanDecision: `将 ${roleId} 的结论合并到现有任务。`,
        affectedTaskIds: [existing.taskId],
        impactType: 'created_task'
      };
      const mergedImpactType = originalImpact.impactType === 'changed_priority' ? 'changed_priority' : 'merged_task';
      existing.contributingRoles.push(roleId);
      existing.contributionImpacts.push({
        roleId,
        changedPlanDecision: mergedImpactType === 'changed_priority'
          ? `该角色的风险判断使合并任务保持 high 优先级。`
          : `该角色的重复结论合并到现有任务，不新增任务。`,
        affectedTaskIds: [existing.taskId],
        impactType: mergedImpactType,
        lowContribution: mergedImpactType === 'merged_task'
      });
      existing.evidence = dedupeEvidence([...existing.evidence, ...(item.evidence || [])]);
      existing.findings = unique([...existing.findings, item.independentFinding].filter(Boolean));
      existing.findingKeys = unique([...existing.findingKeys, findingKey].filter(Boolean));
      existing.triggerReasons = unique([...existing.triggerReasons, ...(item.triggerReasons || [])]);
      existing.goalIds = unique([...existing.goalIds, ...goalIds]);
      if (mergedImpactType === 'changed_priority') existing.priority = 'high';
      continue;
    }
    const taskId = taskIdFor(task);
    const originalImpact = item.decisionImpact || {
      changedPlanDecision: `将 ${item.agentIds[0]} 的可执行任务加入计划优先任务池。`,
      affectedTaskIds: [taskId],
      impactType: 'created_task',
      lowContribution: false
    };
    const priorityLevel = originalImpact.impactType === 'changed_priority' ? 'high' : 'normal';
    records.push({
      taskId,
      task,
      priority: priorityLevel,
      contributingRoles: [...item.agentIds],
      contributionImpacts: [{
        roleId: item.agentIds[0],
        changedPlanDecision: originalImpact.changedPlanDecision,
        affectedTaskIds: [taskId],
        impactType: originalImpact.impactType,
        lowContribution: false
      }],
      evidence: item.evidence || [],
      triggerReasons: item.triggerReasons || [],
      triggerReason: item.triggerReason || (item.triggerReasons || []).join('、'),
      findings: item.independentFinding ? [item.independentFinding] : [],
      independentFinding: item.independentFinding,
      protectedConstraint: item.protectedConstraint,
      scope,
      goalIds,
      taskKey,
      findingKeys: findingKey ? [findingKey] : []
    });
  }
  return records.map((record) => {
    const { taskKey, findingKeys, ...publicRecord } = record;
    return {
      ...publicRecord,
      decisionImpact: publicRecord.contributionImpacts
    };
  });
}

function goalIdsForTask(task, goals = []) {
  return (Array.isArray(goals) ? goals : [])
    .filter((goal) => goal.taskPattern instanceof RegExp && goal.taskPattern.test(task))
    .map((goal) => goal.goalId);
}

function contractTextKey(value) {
  return typeof value === 'string'
    ? value.toLowerCase().replace(/[\s\p{P}\p{S}]+/gu, '')
    : '';
}

function testChecksFor(context) {
  const checks = [];
  if (context.inventory.testFiles.length > 0) {
    const matchedTests = context.impactFiles.filter((file) => file.kind === 'test').map((file) => file.path);
    const tests = matchedTests.length > 0 ? matchedTests.slice(0, 4) : context.inventory.testFiles.slice(0, 4);
    checks.push(`运行现有测试：${tests.join('、')}。`);
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
  } else if (context.intake.answers?.platform === 'Mac' || context.signals.mac) {
    checks.push('发布前再验证版本、签名、公证、Gatekeeper 和分发包。');
  } else if (context.intake.answers?.platform === '网页' || context.signals.web) {
    checks.push('发布前再确认部署环境、隐私说明、监控和回滚方式。');
  } else {
    checks.push('使用方式确定后，再采用对应的构建和发布检查。');
  }
  return checks;
}

function renderTaskPlan(plan) {
  const section = (title, items) => [title, '', ...items.map((item) => `- ${item}`), ''];
  const understanding = [plan.understanding];
  if (plan.goalCoverage?.length > 0) {
    understanding.push(`明确目标覆盖：${plan.goalCoverage.map((goal) => `${goal.goalId}=${goal.status}`).join('、')}`);
  }
  if (plan.executionBoundaries?.length > 0) {
    understanding.push(`执行阶段边界：${plan.executionBoundaries.map((item) => `${item.phase}=${item.status}`).join('、')}`);
  }
  if (plan.pendingDecision) understanding.push(`待确认决定：${plan.pendingDecision}`);
  return [
    '# Jumao Agent Plan',
    '',
    ...section('## 1. 用户想做什么或这次想改什么', [plan.request]),
    ...section('## 2. Jumao 对需求的理解', understanding),
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
    platformPending: context.platformPending,
    pendingDecision: context.pendingDecision,
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
      workspaceKind: context.inspection.workspaceKind,
      platforms: context.platforms,
      negativeSignals: context.negativeSignals
    },
    counts: execution.counts,
    blockingQuestions: unique(execution.agents.flatMap((agent) => agent.blockingQuestions)),
    platformPending: context.platformPending,
    pendingDecision: context.pendingDecision,
    agents: execution.agents.map((agent) => ({
      agentId: agent.agentId,
      agentName: agentName(agent.agentId),
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
    `- platformPending: ${context.platformPending}`,
    ...(context.pendingDecision ? [`- pendingDecision: ${context.pendingDecision}`] : []),
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
        roleId: agent.id,
        groupId: agent.groupId,
        status: 'failed',
        summary: '写入 Agent 计划产物时发生真实错误。',
        triggerReasons: ['runtime-baseline'],
        triggerReason: 'runtime-baseline',
        negativeSignals: context.negativeSignals || [],
        scope: context.scope || { paths: ['**'] },
        intentEvidence: [],
        projectEvidence: [],
        roleEvidence: [{ source: 'runtime:write', detail: '运行已进入产物写入阶段。' }],
        evidence: [{ source: 'runtime:write', detail: '运行已进入产物写入阶段。' }],
        evidenceQuality: { valid: false, validEvidence: [], invalidReasons: ['运行写入失败'] },
        findings: [],
        independentFinding: null,
        decisions: [],
        protections: [],
        protectedConstraint: null,
        tasks: [],
        assessmentOutcome: null,
        generatedTask: null,
        decisionImpact: null,
        changedPlanDecision: null,
        affectedTaskIds: [],
        impactType: null,
        unusedEvidence: true,
        blockingQuestions: [],
        planContribution: null,
        incompleteEvidence: true,
        skippedReason: null,
        error: failure.message
      };
    }
    return existing.get(agent.id) || {
      agentId: agent.id,
      roleId: agent.id,
      groupId: agent.groupId,
      status: 'skipped',
      summary: '',
      triggerReasons: [],
      triggerReason: null,
      negativeSignals: context.negativeSignals || [],
      scope: context.scope || { paths: ['**'] },
      intentEvidence: [],
      projectEvidence: [],
      roleEvidence: [],
      evidence: [],
      evidenceQuality: { valid: false, validEvidence: [], invalidReasons: [] },
      findings: [],
      independentFinding: null,
      decisions: [],
      protections: [],
      protectedConstraint: null,
      tasks: [],
      assessmentOutcome: null,
      generatedTask: null,
      decisionImpact: null,
      changedPlanDecision: null,
      affectedTaskIds: [],
      impactType: null,
      unusedEvidence: false,
      blockingQuestions: [],
      planContribution: null,
      incompleteEvidence: false,
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
    platformPending: context.platformPending,
    pendingDecision: context.pendingDecision,
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
      blockingQuestions: latest.blockingQuestions || manifest.blockingQuestions || [],
      platformPending: latest.platformPending ?? manifest.platformPending ?? false,
      pendingDecision: latest.pendingDecision ?? manifest.pendingDecision ?? null
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
    platformPending: execution.platformPending || false,
    pendingDecision: execution.pendingDecision || null,
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
    platformPending: execution.platformPending || false,
    pendingDecision: execution.pendingDecision || null,
    ...(error ? { error } : {})
  };
}

function finalState(context, counts) {
  return context.blockingQuestions.length > 0 || counts.failed > 0 ? 'blocked' : 'ready';
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
  return context.intake.answers.idea || '项目想法尚未说明。';
}

function understandingSummary(context) {
  if (context.intake.mode === 'existing_project') {
    return '先根据用户描述定位直接相关的代码和测试，只做能验证这次变化的最小改动。';
  }
  const platform = context.intake.answers.platform === 'iPhone'
    ? '先在 iPhone 上使用'
    : context.intake.answers.platform === 'Mac'
      ? '先在 Mac 上使用'
      : context.intake.answers.platform === '网页'
        ? '先通过网页使用'
        : '使用方式暂未确定';
  const firstUse = context.intake.answers.features
    ? `第一阶段先把“${context.intake.answers.features}”整理成一次完整的使用过程`
    : '第一阶段先从项目描述整理一次完整的使用过程，不补写未说明的能力';
  return `${firstUse}，${platform}。`;
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
