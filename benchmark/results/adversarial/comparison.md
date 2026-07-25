# 对抗性案例版本对比

每个期望在运行前已保存到对应 `expected.md`；本报告只记录观察结果，不根据结果修改期望或评分。

## 已确认计划无需变更

- 预期：若所有现有计划正确，相关角色应能记录 assessed_no_change，不新增 priorityTask，也不伪造 decision impact。
- v0.3.1：10 项任务；blocked：0。
- v0.4：5 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、documentation_delivery、cicd_build、security_privacy、project_tech_lead、qa_testing、release_manager。

## 触发词但证据不足

- 预期：“以后可能登录”不是当前需求；没有项目或明确范围证据时，不应生成账号、数据库或隐私任务。
- v0.3.1：22 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、documentation_delivery、backend_engineer、admin_dashboard_product、cicd_build、database_engineer、security_privacy、data_governance_dictionary、privacy_request_ops、support_operations、project_tech_lead、qa_testing、release_manager。

## 角色适用但结论无风险

- 预期：安全角色可完成“已检查、无风险”的评估，不应为了 completed 契约额外创建安全任务或提升优先级。
- v0.3.1：38 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、ip_trademark、product_manager、ui_ux、brand_copywriting、user_research_positioning、design_system_qa、accessibility、documentation_delivery、backend_engineer、admin_dashboard_product、cicd_build、database_engineer、security_privacy、data_governance_dictionary、privacy_request_ops、legal_compliance、support_operations、project_tech_lead、qa_testing、release_manager、sre_stability、remote_config_gray_release。

## 中英文否定作用域歧义

- 预期：“Do not release unless approved / 不要发布，除非负责人确认”与“keep beta release option”冲突；应提出阻塞澄清，而不是猜测 release 是否被禁止。
- v0.3.1：18 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、documentation_delivery、cicd_build、security_privacy、project_tech_lead、qa_testing、release_manager、sre_stability、remote_config_gray_release、device_lab_test_data。

## 相互冲突的约束证据

- 预期：产品资料要求匿名浏览，变更请求又要求所有访问必须登录；应标记冲突并阻塞，不能同时当作可执行约束。
- v0.3.1：22 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、documentation_delivery、backend_engineer、admin_dashboard_product、cicd_build、database_engineer、security_privacy、data_governance_dictionary、privacy_request_ops、support_operations、project_tech_lead、qa_testing、release_manager。

## 同一证据触发多个相似任务

- 预期：多个角色可保留来源，但对同一“本地假账号数据边界”应合并为一个可执行任务，不能拆成重复的字段、数据字典和隐私任务。
- v0.3.1：28 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、accessibility、documentation_delivery、backend_engineer、admin_dashboard_product、cicd_build、database_engineer、security_privacy、data_governance_dictionary、privacy_request_ops、legal_compliance、website_frontend、finance_tax、support_operations、project_tech_lead、qa_testing、release_manager。

## Monorepo 局部约束

- 预期：packages/mobile 的“不得云同步”只约束 mobile；packages/admin 的本地报表变更不应继承该约束。计划必须标出 package 范围。
- v0.3.1：10 项任务；blocked：0。
- v0.4：5 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、documentation_delivery、cicd_build、security_privacy、project_tech_lead、qa_testing、release_manager。

## 不可逆认证与数据迁移

- 预期：认证切换、权限提升和数据迁移必须要求备份、回滚、授权迁移验证与人工确认；不能只输出通用登录或隐私任务。
- v0.3.1：34 项任务；blocked：0。
- v0.4：6 项 priorityTasks；blocked：0；completed：founder_decision、product_manager、ui_ux、user_research_positioning、design_system_qa、accessibility、documentation_delivery、backend_engineer、admin_dashboard_product、cicd_build、database_engineer、security_privacy、data_governance_dictionary、privacy_request_ops、legal_compliance、support_operations、project_tech_lead、qa_testing、release_manager、sre_stability、remote_config_gray_release。
