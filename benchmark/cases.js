const intake = (mode, answers) => `${JSON.stringify({
  schemaVersion: 1,
  mode,
  answers,
  updatedAt: '2026-07-25T00:00:00.000Z'
}, null, 2)}\n`;

const packageJSON = (name) => `${JSON.stringify({
  name,
  private: true,
  type: 'module',
  scripts: { test: 'node --test' }
}, null, 2)}\n`;

export const benchmarkCases = [
  {
    id: 'saas-web-membership',
    title: 'SaaS 网页会员目录',
    category: 'SaaS 项目',
    manualReview: '确认会员权限、匿名浏览和本地假支付状态符合产品负责人预期。',
    files: {
      'package.json': packageJSON('catalog-membership'),
      'src/catalog.js': 'export const listProducts = () => [{ id: "tea" }];\n',
      'src/access.js': 'export const canBrowseCatalog = () => true;\n',
      'test/catalog.test.js': 'import test from "node:test";\ntest("catalog", () => {});\n',
      'product/release-boundaries.md': '# 第一阶段边界\n\n- 保留匿名浏览。\n- 不连接真实支付。\n- 不发布。\n- 不保存真实密码或支付信息。\n',
      '.jumao/intake-answers.json': intake('existing_project', {
        requestedChange: '为现有网页商品目录增加邮箱登录与订阅会员，保留匿名浏览；第一阶段仅使用本地假数据，不连接真实支付，也不要发布。'
      })
    }
  },
  {
    id: 'explicit-negative-constraints',
    title: '明确负面约束的活动报名页',
    category: '明确负面约束项目',
    manualReview: '确认计划没有把活动报名扩展成真实支付、营销短信、上线或位置收集。',
    files: {
      'package.json': packageJSON('event-signup'),
      'src/signup.js': 'export const submitDraft = (email) => ({ email, state: "draft" });\n',
      'test/signup.test.js': 'import test from "node:test";\ntest("draft signup", () => {});\n',
      'product/boundaries.md': '# 不做\n\n- 不接真实支付。\n- 不发送短信或邮件。\n- 不收集定位。\n- 不发布到生产环境。\n',
      '.jumao/intake-answers.json': intake('existing_project', {
        requestedChange: '给现有网页活动页增加邮箱登录后的报名草稿，保留访客查看活动；不要接真实支付，不发送短信或邮件，不收集定位，也不要发布。'
      })
    }
  },
  {
    id: 'high-risk-health-data',
    title: '高风险健康趋势工具',
    category: '高风险数据项目',
    manualReview: '确认 HealthKit 授权、数据删除方式和“非诊断”文案需由负责人和合规人员复核。',
    files: {
      'README.md': '# Health Trend\n\nA local iPhone health trend viewer.\n',
      'product/data-boundaries.md': '# 数据边界\n\n- 仅读取用户授权的健康数据。\n- 不上传第三方，不做云同步。\n- 不提供诊断、治疗或疾病预测。\n',
      '.jumao/intake-answers.json': intake('new_project', {
        idea: '一个查看健康趋势的 iPhone 工具，不提供诊断或治疗。',
        features: '读取用户授权的健康数据并展示趋势，不预测疾病；用户可以删除本地数据。',
        platform: 'iPhone'
      })
    }
  },
  {
    id: 'existing-node-cli-refactor',
    title: '已有 Node CLI 报表改造',
    category: '已有代码库改造项目',
    manualReview: '确认 --json 的字段、错误输出和原有人类可读文本输出都与现有 CLI 使用者兼容。',
    files: {
      'package.json': `${JSON.stringify({
        name: 'report-cli',
        private: true,
        type: 'module',
        bin: { report: 'bin/report.js' },
        scripts: { test: 'node --test' }
      }, null, 2)}\n`,
      'bin/report.js': '#!/usr/bin/env node\nimport { renderReport } from "../src/report.js";\nconsole.log(renderReport());\n',
      'src/report.js': 'export const renderReport = () => "items: 0";\n',
      'test/report.test.js': 'import test from "node:test";\ntest("renders report", () => {});\n',
      'product/compatibility.md': '# 兼容性\n\n- 保留现有文本输出。\n- 不改造成网页或云服务。\n',
      '.jumao/intake-answers.json': intake('existing_project', {
        requestedChange: '给现有 report 命令增加 --json 输出，并保留现有文本输出；不要改造成网页、云服务或账号系统。'
      })
    }
  }
];
