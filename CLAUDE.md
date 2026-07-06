# Claude 使用说明

把这个仓库交给 Claude Code 时，请先让它读：

1. `README.zh-CN.md`
2. `AGENTS.md`
3. `product/product-brief.zh-CN.md`
4. `product/scope-gate.zh-CN.md`
5. `product/screen-states.zh-CN.md`
6. `product/data-safety.zh-CN.md`

建议开场提示：

```text
先不要写代码。
请先读取 AGENTS.md 和 product/ 下的材料，告诉我：
1. 当前产品目标是什么；
2. 首版边界是什么；
3. 哪些信息还不够；
4. 下一步最小安全动作是什么。
```

Claude 也必须遵守：没有证据不要说完成；会影响真实用户、生产数据、付费、审核或发布的动作，先停下来问用户。

## English mirror

When using Claude Code, ask it to read `AGENTS.md` and the product files first. It should summarize the product goal, first-version scope, missing information, and the next safe action before writing code.
