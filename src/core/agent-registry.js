export const agentGroups = [
  { id: 'direction_entity', name: '方向与主体 Agent 组' },
  { id: 'product_design', name: '产品与设计 Agent 组' },
  { id: 'tech_development', name: '技术与开发 Agent 组' },
  { id: 'data_privacy', name: '数据与隐私 Agent 组' },
  { id: 'compliance_health', name: '合规与健康声明 Agent 组' },
  { id: 'platform_qualification', name: '上架与平台资质 Agent 组' },
  { id: 'revenue_operations', name: '收费与运营 Agent 组' },
  { id: 'release_incident', name: '发布与事故 Agent 组' }
];

export const responsibilityAgents = [
  {
    id: 'founder_decision',
    name: '项目负责人 / 创始人 Agent',
    groupId: 'direction_entity',
    plainName: '帮你决定这个项目到底要做到哪一步',
    whenTriggered: ['用户选择公开上线、商业化收费或公司产品', '用户对项目阶段不确定'],
    userEducation: [
      '先决定是自己验证想法，还是要面向真实用户上线。',
      '如果要公司化或收费，主体、预算、边界和风险就要有人拍板。'
    ],
    inferredNeeds: ['项目阶段判断', '首版边界', '商业模式决定', '关键风险清单'],
    requiredFiles: ['Founder Decision Log', 'Project Charter'],
    blockingRules: ['没有项目方向和首版边界，不应开始扩大功能范围。'],
    codexRules: ['没有清楚的项目阶段和首版边界，Codex 不得自行扩大产品范围。'],
    nextSafeQuestions: ['这个项目现在更像自己验证想法，还是准备给真实用户使用？']
  },
  {
    id: 'product_manager',
    name: '产品经理 Agent',
    groupId: 'product_design',
    plainName: '帮你把第一版要做什么讲清楚',
    whenTriggered: ['所有项目默认触发', '用户选择原型、内测或准备发布'],
    userEducation: [
      '第一版要先证明一件最重要的事，不能让 AI 自己补需求。',
      '页面、状态和验收标准讲清楚，后面写代码才不容易跑偏。'
    ],
    inferredNeeds: ['产品简报', '首版范围', '页面清单', '验收标准'],
    requiredFiles: ['product/product-brief.zh-CN.md', 'product/scope-gate.zh-CN.md', 'product/screen-states.zh-CN.md'],
    blockingRules: ['没有首版范围和页面状态，不应开始页面实现。'],
    codexRules: ['没有产品范围和页面状态，Codex 不得自行补功能。'],
    nextSafeQuestions: ['第一版只要用户完成哪一件最重要的事？']
  },
  {
    id: 'project_tech_lead',
    name: '项目经理 / 研发负责人 Agent',
    groupId: 'release_incident',
    plainName: '帮你把这次开发拆成不会失控的小步骤',
    whenTriggered: ['用户选择内测、准备发布、公开上线或公司产品'],
    userEducation: [
      '真实上线前要把任务顺序、风险和验收证据排清楚。',
      '每次只让 AI 做一个小范围，才能知道它有没有真的完成。'
    ],
    inferredNeeds: ['任务顺序', '风险清单', '验收节奏', '阻塞事项'],
    requiredFiles: ['Risk Register', 'Change Log'],
    blockingRules: ['没有任务边界和验收方式，不应进入连续开发。'],
    codexRules: ['Codex 每轮只能执行一个明确的小任务，并报告验证证据。'],
    nextSafeQuestions: ['接下来最小的一步，你想先解决哪个用户问题？']
  },
  {
    id: 'corporate_admin',
    name: '公司注册 / 行政负责人 Agent',
    groupId: 'direction_entity',
    plainName: '帮你判断个人项目和公司项目的主体材料',
    whenTriggered: ['用户选择公司主体项目', '用户选择面向中国大陆用户', '用户选择公开上线或商业化收费'],
    userEducation: [
      '公司产品通常要保持主体名称、平台账号、收款资料和备案材料一致。',
      '这些材料不统一，后面上架、备案和收款容易返工。'
    ],
    inferredNeeds: ['公司主体资料', '平台账号清单', '负责人信息', '材料一致性检查'],
    requiredFiles: ['OWNER_ACCOUNT_REGISTRY.md', 'COMPLIANCE_EVIDENCE_REGISTER.md'],
    blockingRules: ['主体资料不清楚时，不应申请或绑定关键平台账号。'],
    codexRules: ['涉及外部平台账号或主体资料时，Codex 必须先请求人工确认。'],
    nextSafeQuestions: ['这个项目准备以个人名义做，还是以公司名义做？']
  },
  {
    id: 'finance_tax',
    name: '财务 / 记账报税 Agent',
    groupId: 'revenue_operations',
    plainName: '帮你判断收费后钱和账怎么对上',
    whenTriggered: ['用户选择商业化收费', '用户选择买断、订阅或付费功能'],
    userEducation: [
      '只要开始收费，就要考虑收款、退款、发票、平台账单和用户权益是否对得上。',
      '收费功能上线前，先把价格、权益和对账责任讲清楚。'
    ],
    inferredNeeds: ['收入对账', '退款记录', '成本记录', '收款资料'],
    requiredFiles: ['IAP_REVENUE_OPS_CHECKLIST.md'],
    blockingRules: ['没有收费和对账规则，不应打开真实收费。'],
    codexRules: ['没有 IAP_REVENUE_OPS_CHECKLIST.md，不得接入 StoreKit 生产订阅。'],
    nextSafeQuestions: ['用户付费后，应该得到哪些明确权益？']
  },
  {
    id: 'legal_compliance',
    name: '法务 / 合规 Agent',
    groupId: 'compliance_health',
    plainName: '帮你判断哪些承诺和资料不能乱写',
    whenTriggered: ['用户选择公开上线、商业化收费、公司产品、App Store 或中国大陆用户', '用户选择有敏感数据'],
    userEducation: [
      '上线给真实用户前，隐私政策、用户协议、敏感数据说明和承诺边界要先讲清楚。',
      '不能把产品能力写成没有证据的承诺。'
    ],
    inferredNeeds: ['隐私政策', '用户协议', '免责声明', '敏感数据说明'],
    requiredFiles: ['COMPLIANCE_EVIDENCE_REGISTER.md', 'DATA_GOVERNANCE_REGISTER.md'],
    blockingRules: ['没有合规材料，不应发布涉及真实用户和敏感数据的版本。'],
    codexRules: ['涉及真实用户、生产数据、付费、审核或上线时，Codex 必须先请求人工确认。'],
    nextSafeQuestions: ['这个产品会不会让用户依赖某种结果或建议？']
  },
  {
    id: 'ip_trademark',
    name: '知识产权 / 商标 Agent',
    groupId: 'direction_entity',
    plainName: '帮你判断名字、图标和素材有没有后续风险',
    whenTriggered: ['用户选择公开上线、商业化收费或公司产品'],
    userEducation: [
      '公开发布前，名字、图标、字体、图片和域名最好先做基础检查。',
      '品牌材料没想清楚，后面可能影响上架、备案和推广。'
    ],
    inferredNeeds: ['名称检查', '素材来源记录', '域名记录', '商标风险提示'],
    requiredFiles: ['IP Asset Register', 'Domain Register'],
    blockingRules: ['品牌来源不清楚时，不应宣称可商用或正式发布。'],
    codexRules: ['Codex 不得声称素材或品牌已获授权，除非已有明确证据。'],
    nextSafeQuestions: ['这个 App 名称、图标和主要素材来自哪里？']
  },
  {
    id: 'ui_ux',
    name: 'UI / UX 设计师 Agent',
    groupId: 'product_design',
    plainName: '帮你把用户每一步看到什么讲清楚',
    whenTriggered: ['所有项目默认触发', '用户选择原型、内测或准备发布'],
    userEducation: [
      '页面不能只写顺利情况，还要有没数据、失败、权限拒绝和成功后的状态。',
      '用户第一次打开就要知道下一步怎么做。'
    ],
    inferredNeeds: ['页面状态', '权限解释', '错误提示', '成功反馈'],
    requiredFiles: ['product/screen-states.zh-CN.md', 'STATE_MATRIX.md'],
    blockingRules: ['没有页面状态，不应开始写正式页面。'],
    codexRules: ['没有页面状态矩阵，Codex 不得只实现顺利路径。'],
    nextSafeQuestions: ['用户第一次打开时，最应该先看到什么？']
  },
  {
    id: 'website_frontend',
    name: '官网前端 / Web 工程师 Agent',
    groupId: 'platform_qualification',
    plainName: '帮你判断官网、隐私页和支持页要不要准备',
    whenTriggered: ['用户选择 App Store', '用户选择面向中国大陆用户', '用户选择公开上线或公司产品'],
    userEducation: [
      '正式上架通常需要隐私政策 URL 和支持 URL。',
      '面向中国大陆用户时，官网还可能和备案、主体展示相关。'
    ],
    inferredNeeds: ['官网', '隐私政策页面', '支持页面', '删除说明页面'],
    requiredFiles: ['COMPLIANCE_EVIDENCE_REGISTER.md'],
    blockingRules: ['没有可访问的隐私和支持页面，不应提交正式审核。'],
    codexRules: ['没有隐私政策和支持入口证据，Codex 不得声称可正式提审。'],
    nextSafeQuestions: ['用户遇到问题时，应该去哪里找到帮助？']
  },
  {
    id: 'ios_engineer',
    name: 'iOS 工程师 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断 iPhone App 这边要准备哪些能力',
    whenTriggered: ['用户选择 App Store 或 TestFlight', '用户选择 Apple 登录、订阅、健康数据或设备权限'],
    userEducation: [
      'iPhone App 上架前要处理登录、权限、构建、隐私说明和测试账号等细节。',
      '涉及 Apple 登录、订阅或健康数据时，客户端实现不能最后才补。'
    ],
    inferredNeeds: ['iOS 权限说明', '构建配置', '测试账号', '客户端验收'],
    requiredFiles: ['RELEASE_MANAGER_CHECKLIST.md'],
    blockingRules: ['没有发布和测试材料，不应提交 TestFlight 或正式审核。'],
    codexRules: ['没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。'],
    nextSafeQuestions: ['这个 App 在手机上需要用到哪些用户授权？']
  },
  {
    id: 'watchos_engineer',
    name: 'watchOS 工程师 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断第一版要不要支持 Apple Watch',
    whenTriggered: ['用户选择健康数据', '用户提到手表、运动、睡眠或心率相关场景'],
    userEducation: [
      '手表端会增加同步、权限、测试设备和审核说明。',
      '如果第一版没有强理由，可以先明确暂不做手表端。'
    ],
    inferredNeeds: ['watchOS 范围决定', '设备同步说明', '手表测试计划'],
    requiredFiles: ['DEVICE_LAB_TEST_MATRIX.md'],
    blockingRules: ['没有手表范围决定，不应顺手添加手表端功能。'],
    codexRules: ['没有明确范围，Codex 不得自行新增 watchOS 功能。'],
    nextSafeQuestions: ['第一版必须支持手表，还是先只做手机端？']
  },
  {
    id: 'backend_engineer',
    name: '后端工程师 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断什么时候需要账号和服务端能力',
    whenTriggered: ['用户选择要别人登录', '用户选择换手机数据要还在', '用户选择订阅收费', '用户选择客服处理账号问题'],
    userEducation: [
      '如果你要登录、换机恢复、订阅或客服处理账号问题，通常会需要后端、数据库和后台。',
      '现在你不需要先懂这些，我会先把它们标成可能需要，并禁止 Codex 直接写生产后端。'
    ],
    inferredNeeds: ['账号能力', '接口约定', '会员状态', '删除账号流程'],
    requiredFiles: ['DATA_GOVERNANCE_REGISTER.md', 'SUPPORT_REFUND_DELETION_PLAYBOOK.md'],
    blockingRules: ['没有数据治理和账号删除规则，不应写生产账号服务。'],
    codexRules: ['没有 DATA_GOVERNANCE_REGISTER.md，不得新增数据库字段。'],
    nextSafeQuestions: ['用户登录后，需要保留哪些自己的内容？']
  },
  {
    id: 'devops_cloud',
    name: 'DevOps / 云架构 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断正式运行前要准备哪些线上保障',
    whenTriggered: ['用户选择公开上线', '用户选择换手机数据要还在', '用户选择公司产品或中国大陆用户'],
    userEducation: [
      '正式给别人用时，要考虑环境、密钥、备份、恢复、成本和故障处理。',
      '这些不是一开始都要做完，但不能让 Codex 直接部署生产环境。'
    ],
    inferredNeeds: ['运行环境', '密钥管理', '备份恢复', '成本预警', '部署记录'],
    requiredFiles: ['CLOUD_IAM_SECRETS_BACKUP_SPEC.md'],
    blockingRules: ['没有云账号、密钥和备份规范，不得部署生产环境。'],
    codexRules: ['没有 CLOUD_IAM_SECRETS_BACKUP_SPEC.md，不得部署生产环境。'],
    nextSafeQuestions: ['这个项目现在只是本地试用，还是要给外部用户持续使用？']
  },
  {
    id: 'database_engineer',
    name: '数据库工程师 Agent',
    groupId: 'data_privacy',
    plainName: '帮你判断哪些数据会被保存以及怎么删除',
    whenTriggered: ['用户选择要别人登录', '用户选择换手机数据要还在', '用户选择有敏感数据'],
    userEducation: [
      '只要保存用户数据，就要先讲清楚字段、用途、保存位置、保留多久和怎么删除。',
      '不能先让 Codex 建一堆字段，再回头补隐私说明。'
    ],
    inferredNeeds: ['数据字段清单', '保存周期', '删除规则', '备份恢复规则'],
    requiredFiles: ['DATA_GOVERNANCE_REGISTER.md'],
    blockingRules: ['没有数据治理登记，不得新增数据库字段。'],
    codexRules: ['没有 DATA_GOVERNANCE_REGISTER.md，不得新增数据库字段。'],
    nextSafeQuestions: ['哪些内容必须保存，哪些内容可以只留在用户手机上？']
  },
  {
    id: 'algorithm_data',
    name: '算法 / 数据工程师 Agent',
    groupId: 'compliance_health',
    plainName: '帮你判断评分、报告和推荐有没有依据',
    whenTriggered: ['用户选择健康数据', '用户选择金融数据', '用户需要评分、报告、推荐或趋势解释'],
    userEducation: [
      '有评分、报告或推荐时，要说明依据、限制和不能承诺的结果。',
      '能算出结果不等于能对用户做强结论。'
    ],
    inferredNeeds: ['算法说明', '数据质量规则', '结果边界', '版本记录'],
    requiredFiles: ['ALGORITHM_VALIDATION_SPEC.md'],
    blockingRules: ['没有算法和证据说明，不应输出高风险结论。'],
    codexRules: ['没有 ALGORITHM_VALIDATION_SPEC.md，不得新增高风险评分或结论文案。'],
    nextSafeQuestions: ['这个产品会不会给用户评分、报告或建议？']
  },
  {
    id: 'qa_testing',
    name: 'QA 测试 Agent',
    groupId: 'release_incident',
    plainName: '帮你确认上线前有没有真的测过',
    whenTriggered: ['用户选择 TestFlight、App Store、内测或准备发布'],
    userEducation: [
      '上线前不能只测顺利情况，还要测失败、弱网、权限拒绝、退款、注销和无数据。',
      '没有测试证据，就不能说已经准备发布。'
    ],
    inferredNeeds: ['测试计划', '真机检查', '回归结果', '阻断问题清单'],
    requiredFiles: ['DEVICE_LAB_TEST_MATRIX.md', 'RELEASE_MANAGER_CHECKLIST.md'],
    blockingRules: ['没有测试证据，不应提交审核或声称发布就绪。'],
    codexRules: ['没有测试结果和发布清单，Codex 不得声称可提审或可上线。'],
    nextSafeQuestions: ['上线前，你最担心用户在哪一步失败？']
  },
  {
    id: 'security_privacy',
    name: '安全 / 隐私工程师 Agent',
    groupId: 'data_privacy',
    plainName: '帮你避免把用户隐私和敏感数据放到危险位置',
    whenTriggered: ['用户选择登录、敏感数据、公开上线、收费或中国大陆用户'],
    userEducation: [
      '账号、联系方式、健康、定位、身份信息都需要更谨慎处理。',
      '日志、客服后台和第三方工具不能随便看到敏感明细。'
    ],
    inferredNeeds: ['日志脱敏', '权限边界', '敏感数据说明', '安全检查'],
    requiredFiles: ['DATA_GOVERNANCE_REGISTER.md', 'SDK_VENDOR_REGISTER.md'],
    blockingRules: ['没有隐私和安全边界，不应处理敏感数据。'],
    codexRules: ['Codex 不得把密钥、验证码、私钥或敏感样例写进仓库。'],
    nextSafeQuestions: ['哪些信息你觉得用户绝对不希望被别人看到？']
  },
  {
    id: 'app_store_submission',
    name: 'App Store 上架负责人 Agent',
    groupId: 'platform_qualification',
    plainName: '帮你判断上 App Store 要准备什么',
    whenTriggered: ['用户选择准备上 App Store', '用户选择 TestFlight', '用户选择准备发布'],
    userEducation: [
      '如果只是自己手机上跑，可以先不用准备完整上架材料。',
      '如果要上 App Store，通常需要 Apple Developer Program、审核材料、隐私政策、支持 URL、截图和审核说明。'
    ],
    inferredNeeds: ['Apple Developer Program', 'App Store 元数据', '隐私政策 URL', '支持 URL', '审核账号', '截图和 Review Notes'],
    requiredFiles: ['RELEASE_MANAGER_CHECKLIST.md', 'COMPLIANCE_EVIDENCE_REGISTER.md'],
    blockingRules: ['没有发布清单，不得提交 TestFlight 或 App Store 审核包。'],
    codexRules: ['没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。'],
    nextSafeQuestions: ['你只是想给朋友内测，还是准备正式上架？']
  },
  {
    id: 'wechat_open_platform',
    name: '微信开放平台对接负责人 Agent',
    groupId: 'platform_qualification',
    plainName: '帮你判断微信登录要准备什么',
    whenTriggered: ['用户选择要别人登录', '用户选择面向中国大陆用户', '用户提到微信登录'],
    userEducation: [
      '微信登录不是一个按钮，还涉及平台审核、主体一致、回调地址和账号绑定。',
      '密钥不能放进客户端或公开仓库。'
    ],
    inferredNeeds: ['微信开放平台应用', '账号绑定规则', '密钥保存方式', '主体一致检查'],
    requiredFiles: ['SDK_VENDOR_REGISTER.md', 'OWNER_ACCOUNT_REGISTRY.md'],
    blockingRules: ['没有 SDK 登记和账号负责人，不应接入微信登录。'],
    codexRules: ['没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。'],
    nextSafeQuestions: ['用户是否希望用微信作为登录方式之一？']
  },
  {
    id: 'sms_service',
    name: '短信服务对接负责人 Agent',
    groupId: 'platform_qualification',
    plainName: '帮你判断手机号验证码要准备什么',
    whenTriggered: ['用户选择要别人登录', '用户选择面向中国大陆用户', '用户选择手机号登录'],
    userEducation: [
      '手机号验证码会涉及实名材料、签名模板、发送频率、成本和防刷。',
      '短信服务上线前要先想好失败、滥用和费用暴涨怎么处理。'
    ],
    inferredNeeds: ['短信签名', '验证码模板', '发送限制', '成本预警', '失败处理'],
    requiredFiles: ['SDK_VENDOR_REGISTER.md', 'ABUSE_PREVENTION_RULES.md'],
    blockingRules: ['没有 SDK 登记和防滥用规则，不应接入短信验证码。'],
    codexRules: ['没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。'],
    nextSafeQuestions: ['用户是否需要用手机号接收验证码？']
  },
  {
    id: 'health_content',
    name: '健康内容顾问 Agent',
    groupId: 'compliance_health',
    plainName: '帮你把健康表达说得安全一点',
    whenTriggered: ['用户选择健康数据', '用户需要身体状态解释、报告或提醒'],
    userEducation: [
      '健康文案不能制造焦虑，也不能写成诊断、治疗或疾病预警。',
      '要先确定哪些话能说，哪些话不能说。'
    ],
    inferredNeeds: ['健康表达边界', '禁用词', '免责声明', '报告文案审查'],
    requiredFiles: ['HEALTH_CLAIMS_APPROVAL_LOG.md'],
    blockingRules: ['没有健康声明审查，不得新增健康结论或报告文案。'],
    codexRules: ['没有 HEALTH_CLAIMS_APPROVAL_LOG.md，不得新增健康结论、推送文案、报告文案。'],
    nextSafeQuestions: ['这个产品会不会解释用户的身体状态？']
  },
  {
    id: 'analytics_growth',
    name: '数据分析 / 增长 Agent',
    groupId: 'revenue_operations',
    plainName: '帮你判断上线后看哪些反馈和转化',
    whenTriggered: ['用户选择商业化收费', '用户选择公开上线', '用户选择需要反馈或运营'],
    userEducation: [
      '上线后可以看留存、转化和反馈，但不能为了增长乱采敏感明细。',
      '分析事件要先说明用途，避免和隐私承诺冲突。'
    ],
    inferredNeeds: ['反馈分类', '基础指标', '事件说明', '转化观察'],
    requiredFiles: ['DATA_GOVERNANCE_REGISTER.md', 'SDK_VENDOR_REGISTER.md'],
    blockingRules: ['没有数据治理和 SDK 登记，不应接入统计或增长工具。'],
    codexRules: ['没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。'],
    nextSafeQuestions: ['上线后你最想看到哪类用户反馈？']
  },
  {
    id: 'support_operations',
    name: '客服 / 运营 Agent',
    groupId: 'revenue_operations',
    plainName: '帮你判断用户退款、注销和反馈怎么处理',
    whenTriggered: ['用户选择需要客服处理退款、注销、账号或反馈', '用户选择收费或登录'],
    userEducation: [
      '只要有登录或收费，就要提前准备退款、恢复购买、注销和数据删除说明。',
      '客服能看什么、不能看什么，也要先定边界。'
    ],
    inferredNeeds: ['退款指引', '注销流程', '反馈分类', '客服权限边界'],
    requiredFiles: ['SUPPORT_REFUND_DELETION_PLAYBOOK.md'],
    blockingRules: ['没有客服、退款和删除流程，不得上线带登录和订阅的版本。'],
    codexRules: ['没有 SUPPORT_REFUND_DELETION_PLAYBOOK.md，不得上线带登录和订阅的版本。'],
    nextSafeQuestions: ['用户需要找你处理退款、注销、账号问题还是普通反馈？']
  },
  {
    id: 'admin_dashboard_product',
    name: '后台产品 / 内部工具负责人 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断内部人员能看什么、能操作什么',
    whenTriggered: ['用户选择需要客服处理账号、退款、注销或反馈', '用户选择公司产品或公开上线'],
    userEducation: [
      '如果内部人员要处理用户问题，就要先限制能看哪些信息、能做哪些操作。',
      '后台是隐私入口，不能当成随便看的内部页面。'
    ],
    inferredNeeds: ['客服处理范围', '操作记录', '敏感信息隐藏', '内部权限边界'],
    requiredFiles: ['ADMIN_RBAC_AUDIT_SPEC.md', 'DATA_GOVERNANCE_REGISTER.md'],
    blockingRules: ['没有内部权限和审计规则，不应制作生产后台。'],
    codexRules: ['没有 ADMIN_RBAC_AUDIT_SPEC.md，不得上线生产后台。'],
    nextSafeQuestions: ['客服处理问题时，最少需要看到哪些信息？']
  },
  {
    id: 'brand_copywriting',
    name: '品牌 / 文案 Agent',
    groupId: 'product_design',
    plainName: '帮你把对外说法讲得清楚又不过度承诺',
    whenTriggered: ['用户选择公开上线、商业化收费、App Store 或健康数据'],
    userEducation: [
      '对外文案会影响用户理解、审核和合规风险。',
      '尤其是收费、健康和隐私相关文案，不能写成夸大承诺。'
    ],
    inferredNeeds: ['品牌语气', '商店文案', '说明文案', '禁用表达'],
    requiredFiles: ['Brand Voice Guide', 'HEALTH_CLAIMS_APPROVAL_LOG.md'],
    blockingRules: ['没有文案边界，不应发布高风险商店文案。'],
    codexRules: ['Codex 不得编写没有证据支撑的健康、收益或效果承诺。'],
    nextSafeQuestions: ['用户看到一句话介绍时，应该记住什么？']
  },
  {
    id: 'filing_cloud_vendor_support',
    name: '外部备案服务 / 云厂商支持 Agent',
    groupId: 'platform_qualification',
    plainName: '帮你判断中国大陆上线可能要准备哪些备案材料',
    whenTriggered: ['用户选择面向中国大陆用户', '用户选择公司产品或公开上线'],
    userEducation: [
      '面向中国大陆用户时，可能要考虑官网、ICP备案、App备案、隐私 URL 和主体一致。',
      '外部服务可以协助，但最终责任仍在项目主体。'
    ],
    inferredNeeds: ['ICP备案判断', 'App备案判断', '官网主体信息', '备案材料记录'],
    requiredFiles: ['COMPLIANCE_EVIDENCE_REGISTER.md', 'CLOUD_IAM_SECRETS_BACKUP_SPEC.md'],
    blockingRules: ['没有地区和主体判断，不应制定正式发布计划。'],
    codexRules: ['涉及中国大陆发布材料时，Codex 不得声称备案已完成，除非有证据。'],
    nextSafeQuestions: ['这个产品第一批用户会不会主要在中国大陆？']
  },
  {
    id: 'user_research_positioning',
    name: '用户研究 / 市场定位负责人 Agent',
    groupId: 'product_design',
    plainName: '帮你确认到底先服务哪类用户',
    whenTriggered: ['用户选择想法、原型、公开上线或商业化收费'],
    userEducation: [
      '用户越模糊，AI 越容易做成大而空的产品。',
      '先定第一批用户和最痛场景，比先堆功能更重要。'
    ],
    inferredNeeds: ['目标用户', '关键场景', '替代方案', '首批反馈方式'],
    requiredFiles: ['product/product-brief.zh-CN.md'],
    blockingRules: ['没有目标用户和关键场景，不应扩大产品范围。'],
    codexRules: ['Codex 不得把目标用户泛化成所有人。'],
    nextSafeQuestions: ['第一批最想服务的是哪一类人？']
  },
  {
    id: 'design_system_qa',
    name: '设计系统 / Design QA 负责人 Agent',
    groupId: 'product_design',
    plainName: '帮你让界面风格和组件保持一致',
    whenTriggered: ['用户选择原型、内测、准备发布或 App Store'],
    userEducation: [
      '页面多起来后，需要按钮、输入框、状态和文字风格保持一致。',
      '先定基础设计规则，AI 不容易写出一堆互相不一样的页面。'
    ],
    inferredNeeds: ['基础组件', '设计规则', '状态规范', '验收标准'],
    requiredFiles: ['DESIGN_SYSTEM.md', 'STATE_MATRIX.md'],
    blockingRules: ['没有设计规则，不应批量写正式页面。'],
    codexRules: ['Codex 写页面时必须遵守已有页面状态和设计规则。'],
    nextSafeQuestions: ['第一版界面应该更像工具、内容产品，还是消费级 App？']
  },
  {
    id: 'accessibility',
    name: '无障碍 / 可访问性负责人 Agent',
    groupId: 'product_design',
    plainName: '帮你照顾看不清、点不准或需要辅助功能的用户',
    whenTriggered: ['用户选择公开上线、App Store、健康数据或面向广泛用户'],
    userEducation: [
      '正式 App 要考虑字体大小、颜色对比、读屏、触控区域和减少动画。',
      '这不是装饰，而是让更多用户能正常使用。'
    ],
    inferredNeeds: ['字体适配', '读屏文案', '对比度检查', '触控区域检查'],
    requiredFiles: ['Accessibility Checklist'],
    blockingRules: ['没有基础可访问性检查，不应声称体验已完成。'],
    codexRules: ['Codex 不得用颜色作为唯一状态表达。'],
    nextSafeQuestions: ['有没有用户可能在光线差、手忙或身体不舒服时使用？']
  },
  {
    id: 'release_manager',
    name: '发布经理 / Release Manager Agent',
    groupId: 'release_incident',
    plainName: '帮你判断什么时候能提审或上线',
    whenTriggered: ['用户选择 TestFlight、App Store、准备发布、公开上线或商业化收费'],
    userEducation: [
      '上线不是代码写完，还包括版本号、测试、审核材料、回滚和上线窗口。',
      '没有发布清单，就不能说可以提审。'
    ],
    inferredNeeds: ['版本号', '构建记录', '发布清单', '回滚计划', '上线窗口'],
    requiredFiles: ['RELEASE_MANAGER_CHECKLIST.md'],
    blockingRules: ['没有发布清单，不得提交 TestFlight 或 App Store 审核包。'],
    codexRules: ['没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。'],
    nextSafeQuestions: ['这次是想给少量朋友测试，还是正式给所有用户使用？']
  },
  {
    id: 'cicd_build',
    name: 'CI/CD 与构建负责人 Agent',
    groupId: 'tech_development',
    plainName: '帮你判断打包、签名和环境配置是否稳定',
    whenTriggered: ['用户选择 TestFlight、App Store、准备发布或公司产品'],
    userEducation: [
      '提审前要能稳定打包，并知道证书、环境变量和构建记录在哪里。',
      '这些准备不等于要自动化一切，但不能临到提审才发现打不出包。'
    ],
    inferredNeeds: ['构建记录', '证书记录', '环境配置说明', '打包验证'],
    requiredFiles: ['RELEASE_MANAGER_CHECKLIST.md'],
    blockingRules: ['没有构建记录，不应声称可以提交审核。'],
    codexRules: ['Codex 不得把证书、私钥或密钥写进仓库。'],
    nextSafeQuestions: ['现在是否已经能在本机稳定打出可测试版本？']
  },
  {
    id: 'sre_stability',
    name: 'SRE / 线上稳定性负责人 Agent',
    groupId: 'release_incident',
    plainName: '帮你判断上线后出了问题谁能发现和处理',
    whenTriggered: ['用户选择公开上线、商业化收费、登录、换机恢复或公司产品'],
    userEducation: [
      '给真实用户使用后，要知道服务是否正常、错误是否增加、用户是否无法登录或恢复权益。',
      '现在可以先列出风险，不需要一开始做复杂体系。'
    ],
    inferredNeeds: ['监控指标', '告警方式', '故障处理', '复盘记录'],
    requiredFiles: ['INCIDENT_RESPONSE_PLAYBOOK.md', 'CLOUD_IAM_SECRETS_BACKUP_SPEC.md'],
    blockingRules: ['没有故障处理和基本监控，不应声称生产就绪。'],
    codexRules: ['没有 CLOUD_IAM_SECRETS_BACKUP_SPEC.md，不得部署生产环境。'],
    nextSafeQuestions: ['如果用户突然无法登录或付费权益失效，你希望怎么发现？']
  },
  {
    id: 'data_governance_dictionary',
    name: '数据治理 / 数据字典负责人 Agent',
    groupId: 'data_privacy',
    plainName: '帮你把会收集和保存的数据讲清楚',
    whenTriggered: ['用户选择要别人登录', '用户选择换机数据要还在', '用户选择有敏感数据', '用户选择面向中国大陆用户'],
    userEducation: [
      '只要保存用户数据，就要说清楚收集什么、为什么收集、保存在哪里、谁能看、怎么删除。',
      '敏感数据不能让 Codex 随手建字段。'
    ],
    inferredNeeds: ['个人信息清单', '数据字典', '保存周期', '删除规则', '导出规则', '后台可见范围'],
    requiredFiles: ['DATA_GOVERNANCE_REGISTER.md'],
    blockingRules: ['没有数据治理登记，不得新增数据库字段。'],
    codexRules: ['没有 DATA_GOVERNANCE_REGISTER.md，不得新增数据库字段。'],
    nextSafeQuestions: ['用户会主动提供哪些个人信息？']
  },
  {
    id: 'privacy_request_ops',
    name: '隐私请求运营负责人 Agent',
    groupId: 'data_privacy',
    plainName: '帮你处理用户要查看、删除或注销自己的数据',
    whenTriggered: ['用户选择要别人登录', '用户选择需要客服处理注销或账号问题', '用户选择有敏感数据'],
    userEducation: [
      '用户登录后，通常需要能注销账号、删除数据、撤回授权或询问隐私问题。',
      '这些流程不能只写在政策里，要能真的执行。'
    ],
    inferredNeeds: ['注销流程', '删除记录', '隐私请求登记', '客服处理边界'],
    requiredFiles: ['SUPPORT_REFUND_DELETION_PLAYBOOK.md', 'DATA_GOVERNANCE_REGISTER.md'],
    blockingRules: ['没有删除和注销流程，不应上线带登录的版本。'],
    codexRules: ['没有 SUPPORT_REFUND_DELETION_PLAYBOOK.md，不得上线带登录和订阅的版本。'],
    nextSafeQuestions: ['用户想注销或删除数据时，应该怎么联系你？']
  },
  {
    id: 'sdk_vendor_governance',
    name: 'SDK / 供应商治理负责人 Agent',
    groupId: 'data_privacy',
    plainName: '帮你判断第三方工具会拿到哪些数据',
    whenTriggered: ['用户选择微信、短信、统计、崩溃监控、客服工具、敏感数据或中国大陆用户'],
    userEducation: [
      '第三方工具可能接触设备信息、账号信息或行为数据。',
      '引入前要记录用途、数据范围、隐私政策和退出方案。'
    ],
    inferredNeeds: ['SDK 清单', '供应商用途', '数据范围', '隐私链接', '退出方案'],
    requiredFiles: ['SDK_VENDOR_REGISTER.md'],
    blockingRules: ['没有 SDK 登记，不得引入第三方 SDK。'],
    codexRules: ['没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。'],
    nextSafeQuestions: ['你是否准备接入微信、短信、统计、客服或崩溃分析工具？']
  },
  {
    id: 'medical_claims_review',
    name: '医疗监管 / 健康声明审查负责人 Agent',
    groupId: 'compliance_health',
    plainName: '帮你避免把健康功能写成医疗承诺',
    whenTriggered: ['用户选择健康数据', '用户需要健康结论、报告、评分或推送提醒'],
    userEducation: [
      '健康数据和健康结论风险很高，不能随便写诊断、治疗、疾病预警或医疗承诺。',
      '低分、异常、风险这些词可能让用户误解，需要先定义表达边界。'
    ],
    inferredNeeds: ['健康文案边界', '免责声明', '健康声明审查记录', '证据等级', '禁用词清单'],
    requiredFiles: ['HEALTH_CLAIMS_APPROVAL_LOG.md'],
    blockingRules: ['没有健康声明审查，不得新增健康结论、推送文案、报告文案。'],
    codexRules: ['没有 HEALTH_CLAIMS_APPROVAL_LOG.md，不得新增健康结论、推送文案、报告文案。'],
    nextSafeQuestions: ['这个产品会不会给用户身体状态的判断或提醒？']
  },
  {
    id: 'algorithm_validation_evidence',
    name: '算法验证 / 科学证据负责人 Agent',
    groupId: 'compliance_health',
    plainName: '帮你判断算法结果有没有证据边界',
    whenTriggered: ['用户选择健康数据', '用户需要评分、趋势、预测、报告或建议'],
    userEducation: [
      '算法输出要说明样本不足、误差、适用范围和不能代表什么。',
      '如果没有证据边界，就不能把结果写得像确定结论。'
    ],
    inferredNeeds: ['验证样例', '证据登记', '算法版本', '置信度说明'],
    requiredFiles: ['ALGORITHM_VALIDATION_SPEC.md', 'HEALTH_CLAIMS_APPROVAL_LOG.md'],
    blockingRules: ['没有算法验证，不应输出高风险趋势或建议。'],
    codexRules: ['没有 ALGORITHM_VALIDATION_SPEC.md，不得新增高风险评分或建议。'],
    nextSafeQuestions: ['这个结果是给用户参考，还是会影响用户做重要决定？']
  },
  {
    id: 'iap_revenue_ops',
    name: 'IAP / 订阅营收负责人 Agent',
    groupId: 'revenue_operations',
    plainName: '帮你判断 iOS 收费要准备什么',
    whenTriggered: ['用户选择要收费', '用户选择订阅会员', '用户选择商业化收费', '用户选择 App Store 上架并卖数字服务'],
    userEducation: [
      '如果 iOS App 内卖数字会员，通常涉及 Apple 内购。',
      '订阅不是一个按钮，还包括商品、权益、退款、恢复购买、过期状态和财务对账。'
    ],
    inferredNeeds: ['IAP 商品', '会员权益规则', '恢复购买', '退款流程', '订阅状态', '财务对账'],
    requiredFiles: ['IAP_REVENUE_OPS_CHECKLIST.md', 'SUPPORT_REFUND_DELETION_PLAYBOOK.md'],
    blockingRules: ['没有 IAP 营收清单，不得接入 StoreKit 生产订阅。'],
    codexRules: ['没有 IAP_REVENUE_OPS_CHECKLIST.md，不得接入 StoreKit 生产订阅。'],
    nextSafeQuestions: ['付费用户比免费用户多哪些明确权益？']
  },
  {
    id: 'abuse_risk_control',
    name: '反滥用 / 风控负责人 Agent',
    groupId: 'data_privacy',
    plainName: '帮你避免验证码、账号和接口被刷',
    whenTriggered: ['用户选择手机号登录', '用户选择公开上线、收费或中国大陆用户'],
    userEducation: [
      '验证码、账号注册、优惠和接口都可能被滥用。',
      '先定频率限制和异常处理，可以减少账单爆掉和用户被影响。'
    ],
    inferredNeeds: ['发送限制', '异常告警', '黑名单规则', '成本预警'],
    requiredFiles: ['ABUSE_PREVENTION_RULES.md'],
    blockingRules: ['没有反滥用规则，不应上线短信或公开账号入口。'],
    codexRules: ['Codex 不得上线没有频率限制的验证码或公开写入口。'],
    nextSafeQuestions: ['有没有入口会被陌生人反复提交或反复请求？']
  },
  {
    id: 'remote_config_gray_release',
    name: '配置中心 / 灰度负责人 Agent',
    groupId: 'release_incident',
    plainName: '帮你判断上线后哪些东西需要逐步放开',
    whenTriggered: ['用户选择公开上线、商业化收费、健康数据或准备发布'],
    userEducation: [
      '新功能可以先给少量用户使用，观察没有问题再扩大。',
      '影响收费、健康解释或关键流程的配置，不能无记录随便改。'
    ],
    inferredNeeds: ['灰度计划', '功能开关', '配置记录', '回滚方案'],
    requiredFiles: ['RELEASE_MANAGER_CHECKLIST.md', 'INCIDENT_RESPONSE_PLAYBOOK.md'],
    blockingRules: ['没有灰度和回滚计划，不应直接全量上线高风险功能。'],
    codexRules: ['没有 RELEASE_MANAGER_CHECKLIST.md，不得提交 TestFlight 或 App Store 审核包。'],
    nextSafeQuestions: ['正式上线时，你希望先给少量用户试，还是一次性全量开放？']
  },
  {
    id: 'device_lab_test_data',
    name: '设备实验室 / 测试数据负责人 Agent',
    groupId: 'release_incident',
    plainName: '帮你准备真实设备和测试数据',
    whenTriggered: ['用户选择 App Store、TestFlight、健康数据或准备发布'],
    userEducation: [
      '权限、健康数据、订阅和登录最好在真实设备上验证。',
      '没有测试账号和测试数据，审核和用户使用时容易卡住。'
    ],
    inferredNeeds: ['真机清单', '测试账号', '模拟数据', '审核演示路径'],
    requiredFiles: ['DEVICE_LAB_TEST_MATRIX.md'],
    blockingRules: ['没有测试设备和测试数据，不应声称审核准备完成。'],
    codexRules: ['Codex 必须报告真实验证证据，不能把未测内容写成已通过。'],
    nextSafeQuestions: ['你准备用哪些手机或账号来验证第一版？']
  },
  {
    id: 'documentation_delivery',
    name: '文档 / 交付物负责人 Agent',
    groupId: 'product_design',
    plainName: '帮你把给 AI 和给人的说明整理清楚',
    whenTriggered: ['所有项目默认触发', '用户选择交给 Codex、Claude 或 Cursor 开发'],
    userEducation: [
      'AI 写代码前要读到清楚的目标、边界、数据规则和验收证据。',
      '文档过期时，AI 会按错误信息继续写。'
    ],
    inferredNeeds: ['任务包', '决策记录', '变更记录', '验收证据'],
    requiredFiles: ['Documentation Index', 'Decision Log'],
    blockingRules: ['没有清楚任务包，不应让 AI 直接改代码。'],
    codexRules: ['Codex 必须先读取任务包并总结目标、边界、风险和下一步。'],
    nextSafeQuestions: ['这次要交给 AI 的最小任务是什么？']
  },
  {
    id: 'software_copyright_qualification',
    name: '软件著作权 / 资质留存负责人 Agent',
    groupId: 'direction_entity',
    plainName: '帮你判断商业项目要不要留存版本和资质材料',
    whenTriggered: ['用户选择公司产品、商业化收费或公开上线'],
    userEducation: [
      '商业项目常常需要留存版本、截图、说明和材料，方便后续资质或合作。',
      '这不一定是第一天必须办，但要知道证据从哪里来。'
    ],
    inferredNeeds: ['版本证据', '功能说明', '截图材料', '资质判断'],
    requiredFiles: ['Version Evidence Package'],
    blockingRules: ['没有证据留存，不应声称资质材料已准备好。'],
    codexRules: ['Codex 不得声称软著或资质已办理，除非有明确证据。'],
    nextSafeQuestions: ['这个项目后面是否可能用于公司合作、融资或资质申请？']
  },
  {
    id: 'procurement_contract_vendor',
    name: '采购 / 合同 / 供应商负责人 Agent',
    groupId: 'direction_entity',
    plainName: '帮你判断买服务、找外包或接供应商时要留什么记录',
    whenTriggered: ['用户选择公司产品、商业化收费、中国大陆用户或第三方服务'],
    userEducation: [
      '云服务、短信、设计、法务、备案和外包都可能涉及合同、付款、账号和退出方案。',
      '供应商不是买完就结束，还要知道谁负责、怎么停用、费用怎么算。'
    ],
    inferredNeeds: ['供应商清单', '付款记录', '合同记录', '退出方案'],
    requiredFiles: ['Vendor Register', 'Contract Register', 'SDK_VENDOR_REGISTER.md'],
    blockingRules: ['没有供应商记录，不应接入关键外部服务。'],
    codexRules: ['没有 SDK_VENDOR_REGISTER.md，不得引入第三方 SDK。'],
    nextSafeQuestions: ['这个项目现在会不会购买短信、云服务、设计、备案或客服工具？']
  }
];

const baseAgentIds = ['founder_decision', 'product_manager', 'ui_ux', 'documentation_delivery'];

const triggerRules = [
  {
    matches: (answers) => includesAny(answers.storePlan, ['app_store', 'testflight']),
    agentIds: ['app_store_submission', 'ios_engineer', 'release_manager', 'qa_testing', 'legal_compliance']
  },
  {
    matches: (answers) => answers.loginNeeded === true,
    agentIds: ['backend_engineer', 'data_governance_dictionary', 'privacy_request_ops', 'security_privacy']
  },
  {
    matches: (answers) => includesAny(answers.chargingPlan, ['subscription', 'paid']),
    agentIds: ['iap_revenue_ops', 'finance_tax', 'support_operations']
  },
  {
    matches: (answers) => includesAny(answers.crossDeviceData, ['needed']),
    agentIds: ['backend_engineer', 'database_engineer', 'devops_cloud', 'data_governance_dictionary']
  },
  {
    matches: (answers) => includesAny(answers.sensitiveData, ['health']),
    agentIds: [
      'health_content',
      'medical_claims_review',
      'algorithm_validation_evidence',
      'security_privacy',
      'sdk_vendor_governance'
    ]
  },
  {
    matches: (answers) => answers.chinaUsers === true,
    agentIds: ['legal_compliance', 'filing_cloud_vendor_support', 'website_frontend', 'sms_service', 'wechat_open_platform']
  },
  {
    matches: (answers) => includesAny(answers.supportNeeds, ['refund', 'deletion', 'account']),
    agentIds: ['support_operations', 'privacy_request_ops', 'admin_dashboard_product']
  }
];

export function getAgentById(id) {
  return responsibilityAgents.find((agent) => agent.id === id);
}

export function getAgentsByGroup(groupId) {
  return responsibilityAgents.filter((agent) => agent.groupId === groupId);
}

export function getTriggeredAgents(answers = {}) {
  const triggeredIds = new Set(baseAgentIds);

  for (const rule of triggerRules) {
    if (rule.matches(answers || {})) {
      for (const id of rule.agentIds) triggeredIds.add(id);
    }
  }

  return responsibilityAgents.filter((agent) => triggeredIds.has(agent.id));
}

function includesAny(value, expectedValues) {
  const values = Array.isArray(value) ? value : [value];
  return values
    .filter((item) => item !== undefined && item !== null)
    .map((item) => String(item).toLowerCase())
    .some((item) => expectedValues.includes(item));
}
