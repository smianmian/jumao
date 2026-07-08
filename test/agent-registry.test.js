import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {
  agentGroups,
  getAgentById,
  getAgentsByGroup,
  getTriggeredAgents,
  responsibilityAgents
} from '../src/core/agent-registry.js';

const requiredAgentFields = [
  'id',
  'name',
  'groupId',
  'plainName',
  'whenTriggered',
  'userEducation',
  'inferredNeeds',
  'requiredFiles',
  'blockingRules',
  'codexRules',
  'nextSafeQuestions'
];

const requiredAgentIds = [
  'founder_decision',
  'product_manager',
  'project_tech_lead',
  'corporate_admin',
  'finance_tax',
  'legal_compliance',
  'ip_trademark',
  'ui_ux',
  'website_frontend',
  'ios_engineer',
  'watchos_engineer',
  'backend_engineer',
  'devops_cloud',
  'database_engineer',
  'algorithm_data',
  'qa_testing',
  'security_privacy',
  'app_store_submission',
  'wechat_open_platform',
  'sms_service',
  'health_content',
  'analytics_growth',
  'support_operations',
  'admin_dashboard_product',
  'brand_copywriting',
  'filing_cloud_vendor_support',
  'user_research_positioning',
  'design_system_qa',
  'accessibility',
  'release_manager',
  'cicd_build',
  'sre_stability',
  'data_governance_dictionary',
  'privacy_request_ops',
  'sdk_vendor_governance',
  'medical_claims_review',
  'algorithm_validation_evidence',
  'iap_revenue_ops',
  'abuse_risk_control',
  'remote_config_gray_release',
  'device_lab_test_data',
  'documentation_delivery',
  'software_copyright_qualification',
  'procurement_contract_vendor'
];

const forbiddenQuestionPatterns = [
  /要不要后端/,
  /要不要数据库/,
  /要不要云服务器/,
  /要不要 RBAC/i,
  /要不要 IAP/i,
  /要不要 SRE/i,
  /要不要 CI\/CD/i
];

const forbiddenDocPatterns = [
  ...forbiddenQuestionPatterns,
  /原责任/,
  /还必须负责/,
  /官方依据索引/
];

const agentsDocUrl = new URL('../docs/agents.zh-CN.md', import.meta.url);

function includesText(values, text) {
  return values.some((value) => value.includes(text));
}

test('agent groups define the eight front-stage groups', () => {
  assert.equal(agentGroups.length, 8);
  assert.deepEqual(
    agentGroups.map((group) => [group.id, group.name]),
    [
      ['direction_entity', '方向与主体 Agent 组'],
      ['product_design', '产品与设计 Agent 组'],
      ['tech_development', '技术与开发 Agent 组'],
      ['data_privacy', '数据与隐私 Agent 组'],
      ['compliance_health', '合规与健康声明 Agent 组'],
      ['platform_qualification', '上架与平台资质 Agent 组'],
      ['revenue_operations', '收费与运营 Agent 组'],
      ['release_incident', '发布与事故 Agent 组']
    ]
  );
});

test('responsibility agents define the full 44-agent registry', () => {
  assert.equal(responsibilityAgents.length, 44);
  assert.deepEqual(
    responsibilityAgents.map((agent) => agent.id),
    requiredAgentIds
  );
});

test('agent ids are unique', () => {
  const ids = responsibilityAgents.map((agent) => agent.id);
  assert.equal(new Set(ids).size, ids.length);
});

test('each agent has required fields and machine-readable arrays', () => {
  for (const agent of responsibilityAgents) {
    for (const field of requiredAgentFields) {
      assert.ok(Object.hasOwn(agent, field), `${agent.id} is missing ${field}`);
    }

    assert.match(agent.id, /^[a-z0-9]+(?:_[a-z0-9]+)*$/);
    assert.equal(typeof agent.name, 'string');
    assert.equal(typeof agent.groupId, 'string');
    assert.equal(typeof agent.plainName, 'string');
    assert.ok(agent.plainName.length > 0);

    for (const field of [
      'whenTriggered',
      'userEducation',
      'inferredNeeds',
      'requiredFiles',
      'blockingRules',
      'codexRules',
      'nextSafeQuestions'
    ]) {
      assert.ok(Array.isArray(agent[field]), `${agent.id}.${field} should be an array`);
      assert.ok(agent[field].length > 0, `${agent.id}.${field} should not be empty`);
      assert.ok(agent[field].every((item) => typeof item === 'string' && item.length > 0));
    }
  }
});

test('each agent groupId exists', () => {
  const groupIds = new Set(agentGroups.map((group) => group.id));

  for (const agent of responsibilityAgents) {
    assert.ok(groupIds.has(agent.groupId), `${agent.id} has unknown group ${agent.groupId}`);
  }
});

test('next safe questions avoid forbidden technical wording', () => {
  for (const agent of responsibilityAgents) {
    for (const question of agent.nextSafeQuestions) {
      for (const pattern of forbiddenQuestionPatterns) {
        assert.doesNotMatch(question, pattern, `${agent.id} asks a forbidden technical question`);
      }
    }
  }
});

test('specific governance gates are present on the right agents', () => {
  assert.ok(includesText(getAgentById('app_store_submission').requiredFiles, 'RELEASE_MANAGER_CHECKLIST.md'));
  assert.ok(includesText(getAgentById('app_store_submission').codexRules, 'RELEASE_MANAGER_CHECKLIST.md'));

  assert.ok(includesText(getAgentById('data_governance_dictionary').requiredFiles, 'DATA_GOVERNANCE_REGISTER.md'));
  assert.ok(includesText(getAgentById('data_governance_dictionary').codexRules, 'DATA_GOVERNANCE_REGISTER.md'));

  assert.ok(includesText(getAgentById('sdk_vendor_governance').requiredFiles, 'SDK_VENDOR_REGISTER.md'));
  assert.ok(includesText(getAgentById('sdk_vendor_governance').codexRules, 'SDK_VENDOR_REGISTER.md'));

  assert.ok(includesText(getAgentById('medical_claims_review').requiredFiles, 'HEALTH_CLAIMS_APPROVAL_LOG.md'));
  assert.ok(includesText(getAgentById('medical_claims_review').codexRules, 'HEALTH_CLAIMS_APPROVAL_LOG.md'));

  assert.ok(includesText(getAgentById('iap_revenue_ops').requiredFiles, 'IAP_REVENUE_OPS_CHECKLIST.md'));
  assert.ok(includesText(getAgentById('iap_revenue_ops').codexRules, 'IAP_REVENUE_OPS_CHECKLIST.md'));

  assert.ok(includesText(getAgentById('devops_cloud').requiredFiles, 'CLOUD_IAM_SECRETS_BACKUP_SPEC.md'));
  assert.ok(includesText(getAgentById('devops_cloud').codexRules, 'CLOUD_IAM_SECRETS_BACKUP_SPEC.md'));
});

test('group lookup returns agents from that group only', () => {
  const platformAgents = getAgentsByGroup('platform_qualification');

  assert.ok(platformAgents.length > 0);
  assert.ok(platformAgents.every((agent) => agent.groupId === 'platform_qualification'));
  assert.ok(platformAgents.some((agent) => agent.id === 'app_store_submission'));
});

test('triggered agents cover app store, login, subscription, health, and China answers', () => {
  const agents = getTriggeredAgents({
    projectStage: 'prototype',
    launchIntent: 'public_launch',
    storePlan: 'app_store',
    ownerType: 'company',
    loginNeeded: true,
    chargingPlan: 'subscription',
    crossDeviceData: 'needed',
    sensitiveData: ['health'],
    chinaUsers: true,
    supportNeeds: ['refund', 'deletion', 'account']
  });
  const ids = agents.map((agent) => agent.id);

  for (const expectedId of [
    'app_store_submission',
    'ios_engineer',
    'release_manager',
    'qa_testing',
    'legal_compliance',
    'backend_engineer',
    'data_governance_dictionary',
    'privacy_request_ops',
    'security_privacy',
    'iap_revenue_ops',
    'finance_tax',
    'support_operations',
    'database_engineer',
    'devops_cloud',
    'health_content',
    'medical_claims_review',
    'algorithm_validation_evidence',
    'sdk_vendor_governance',
    'filing_cloud_vendor_support',
    'website_frontend',
    'sms_service',
    'wechat_open_platform',
    'admin_dashboard_product'
  ]) {
    assert.ok(ids.includes(expectedId), `${expectedId} should be triggered`);
  }
});

test('triggered agents return baseline guidance for empty answers', () => {
  const agents = getTriggeredAgents();
  const ids = agents.map((agent) => agent.id);

  assert.ok(ids.length > 0);
  assert.ok(ids.includes('founder_decision'));
  assert.ok(ids.includes('product_manager'));
  assert.ok(ids.includes('ui_ux'));
  assert.ok(ids.includes('documentation_delivery'));
});

test('Chinese agent docs explain all built-in agents for non-programmers', () => {
  assert.ok(fs.existsSync(agentsDocUrl));

  const doc = fs.readFileSync(agentsDocUrl, 'utf8');

  assert.match(doc, /你不用雇 44 个人/);

  for (const group of agentGroups) {
    assert.ok(doc.includes(group.name), `docs should mention ${group.name}`);
  }

  for (const agent of responsibilityAgents) {
    assert.ok(
      doc.includes(agent.name) || doc.includes(agent.plainName),
      `docs should mention ${agent.name} or ${agent.plainName}`
    );
  }

  for (const pattern of forbiddenDocPatterns) {
    assert.doesNotMatch(doc, pattern);
  }
});
