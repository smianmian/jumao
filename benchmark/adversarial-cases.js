const intake = (mode, answers) => `${JSON.stringify({ schemaVersion: 1, mode, answers, updatedAt: '2026-07-25T00:00:00.000Z' }, null, 2)}\n`;
const packageJSON = (name, extra = {}) => `${JSON.stringify({ name, private: true, type: 'module', scripts: { test: 'node --test' }, ...extra }, null, 2)}\n`;

export const adversarialCases = [
  {
    id: 'assessed-no-change',
    title: '已确认计划无需变更',
    expected: '若所有现有计划正确，相关角色应能记录 assessed_no_change，不新增 priorityTask，也不伪造 decision impact。',
    files: {
      'package.json': packageJSON('stable-cli', { bin: { stable: 'bin/stable.js' } }),
      'bin/stable.js': '#!/usr/bin/env node\nconsole.log("stable");\n',
      'test/stable.test.js': 'import test from "node:test";\ntest("stable", () => {});\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '复核现有 stable 命令计划；已确认目标、约束和测试都正确，本次不需要任何代码或计划变化。' })
    }
  },
  {
    id: 'triggered-insufficient-evidence',
    title: '触发词但证据不足',
    expected: '“以后可能登录”不是当前需求；没有项目或明确范围证据时，不应生成账号、数据库或隐私任务。',
    files: {
      'package.json': packageJSON('notes-cli', { bin: { notes: 'bin/notes.js' } }),
      'bin/notes.js': '#!/usr/bin/env node\nconsole.log("notes");\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '修正文案；以后可能考虑 login，但当前不做账号、数据库或任何登录流程。' })
    }
  },
  {
    id: 'applicable-no-risk',
    title: '角色适用但结论无风险',
    expected: '安全角色可完成“已检查、无风险”的评估，不应为了 completed 契约额外创建安全任务或提升优先级。',
    files: {
      'package.json': packageJSON('local-exporter'),
      'src/export.js': 'export const exportNames = (names) => names.join("\\n");\n',
      'test/export.test.js': 'import test from "node:test";\ntest("export", () => {});\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '审核本地导出工具的安全边界：只处理公开示例名称，没有账号、权限、网络或敏感数据；不需要改动。' })
    }
  },
  {
    id: 'bilingual-negation-ambiguity',
    title: '中英文否定作用域歧义',
    expected: '“Do not release unless approved / 不要发布，除非负责人确认”与“keep beta release option”冲突；应提出阻塞澄清，而不是猜测 release 是否被禁止。',
    files: {
      'package.json': packageJSON('beta-web'),
      'src/page.js': 'export const page = () => "beta";\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: 'Do not release unless approved；不要发布，除非负责人确认；但 keep the beta release option for later。' })
    }
  },
  {
    id: 'conflicting-evidence',
    title: '相互冲突的约束证据',
    expected: '产品资料要求匿名浏览，变更请求又要求所有访问必须登录；应标记冲突并阻塞，不能同时当作可执行约束。',
    files: {
      'package.json': packageJSON('catalog-conflict'),
      'src/access.js': 'export const canBrowse = () => true;\n',
      'product/boundaries.md': '# 边界\n\n- 必须保留匿名浏览。\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '所有访问都必须登录，禁止匿名浏览。' })
    }
  },
  {
    id: 'overlapping-role-tasks',
    title: '同一证据触发多个相似任务',
    expected: '多个角色可保留来源，但对同一“本地假账号数据边界”应合并为一个可执行任务，不能拆成重复的字段、数据字典和隐私任务。',
    files: {
      'package.json': packageJSON('local-membership'),
      'src/access.js': 'export const canBrowse = () => true;\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '给本地网页目录增加 login 和 membership；只用本地假账号，不接真实支付，保留匿名浏览。' })
    }
  },
  {
    id: 'monorepo-scoped-constraint',
    title: 'Monorepo 局部约束',
    expected: 'packages/mobile 的“不得云同步”只约束 mobile；packages/admin 的本地报表变更不应继承该约束。计划必须标出 package 范围。',
    files: {
      'package.json': packageJSON('workspace-root', { workspaces: ['packages/*'] }),
      'packages/mobile/package.json': packageJSON('mobile'),
      'packages/mobile/product-boundaries.md': '# Mobile\n\n- 不得云同步。\n',
      'packages/admin/package.json': packageJSON('admin'),
      'packages/admin/src/report.js': 'export const report = () => "admin";\n',
      'packages/admin/test/report.test.js': 'import test from "node:test";\ntest("admin report", () => {});\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '只修改 packages/admin 的 report 输出，保留文本格式。' })
    }
  },
  {
    id: 'irreversible-auth-migration',
    title: '不可逆认证与数据迁移',
    expected: '认证切换、权限提升和数据迁移必须要求备份、回滚、授权迁移验证与人工确认；不能只输出通用登录或隐私任务。',
    files: {
      'package.json': packageJSON('account-migration'),
      'src/users.js': 'export const users = [];\n',
      'test/users.test.js': 'import test from "node:test";\ntest("users", () => {});\n',
      'product/data-risk.md': '# 风险\n\n- 迁移会改变已有账号权限。\n- 未确认前不得执行不可逆写入。\n',
      '.jumao/intake-answers.json': intake('existing_project', { requestedChange: '把现有账号切换到新的认证方式，迁移用户权限和历史数据；该操作不可逆，涉及真实用户。' })
    }
  }
];
