# Jumao 橘猫

[English](README.md)

**公开 Preview · [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

## 橘猫是什么？

**橘猫帮助不会写代码的人，通过 AI 完成 App 从想法到上线。**

你用日常语言说想做什么。橘猫把它整理成清楚的计划和任务包。你把任务包交给
**AI 编程 Agent**（例如 Codex、Claude Code、Cursor）。**写代码的是 Agent**；
「做成什么样、这版先不做什么、怎样算完成」仍由你把关。上线、收费、真实用户相关
动作也要你确认。

再往下说一层：橘猫是 **AI Coding Agent 的决策和交付控制层**——在 Agent 改文件
之前，先把目标、边界和证据钉住；Agent 声称做完后，还可以独立核对。

橘猫在**你自己的电脑上**运行。规划不调用橘猫的云端 AI 接口，不会偷偷替你上架或
向用户收费。

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="橘猫" width="280">

## 为什么需要它

AI **写代码很快**。如果没有钉死的第一版范围，它也容易：

- 自己加你没要的功能  
- 忽略「这版先不做」  
- 没有证据就说「做完了」  

橘猫是**写代码之前**的一步，让 Agent 接到的是更小、可核对的任务。

## 主路径：想法 → 上线

每个用户应先看到这条产品路径：

```text
  想法
    → 橘猫理解你
    → 生成方案 / 任务包
    → AI 开发（同一文件夹）
    → 验证，再由你决定上线
```

| 阶段 | 发生什么 |
|------|----------|
| **想法** | 你知道想做什么（或这次改什么），哪怕还不完整。 |
| **橘猫理解** | 普通问题 + 项目文件夹里能看见的信息。 |
| **生成方案** | 你能读懂的计划，以及 Agent 能跟着走的任务包。 |
| **AI 开发** | Codex / Claude Code / Cursor 等在**同一文件夹**里按包实现。 |
| **验证与上线** | 可选核对 Agent 的完成说法；**上线 / 真实用户 / 钱仍由你决定**。 |

**更想用 Mac 应用？** 下载
[**Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)，
选文件夹 → 答几题 → 看方案 → **交给 AI Coding Agent**（说明里会以 Codex 等为
示例，不绑定单一工具）。

完整说明：**[开始使用](docs/getting-started.zh-CN.md)**。

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="新项目的普通问题" width="640">

## 安装（v0.4.0-rc.2 Preview）

### Jumao Cat for macOS（多数人推荐）

[**下载 Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)

1. 下载 `JumaoCat-v0.4.0-rc.2-arm64.zip`
2. 解压 → 把 `Jumao Cat.app` 拖进 **「应用程序」**
3. 从 **「应用程序」** 打开

要求：macOS 14+、Apple 芯片。已签名并公证。用 App **不必**先装 Node。

### CLI

```bash
npm install -g jumao@rc
```

安装 Preview **0.4.0-rc.2**（`rc` dist-tag）。

更早版本（如 v0.3.1）只作历史对照。**新用户从 v0.4.0-rc.2 开始。**

## 给开发者：CLI 使用方式

在理解上面的产品路径之后，终端流程是：

```bash
npm install -g jumao@rc

# 1) 新建产品工作区
jumao new "我的第一个App" --dir ./my-first-app
cd ./my-first-app

# 2) 普通语言访谈
jumao interview .

# 3) 严格检查：关键文件是否齐全、是否为空
jumao check --strict .

# 4) 结构化缺口报告（主路径用 audit）
jumao audit . --write

# 5) 打给 AI Coding Agent 的任务包（codex 只是目标之一）
jumao pack --target codex .
# 也可：--target claude | --target cursor
```

| 步骤 | 命令 | 人话 |
|------|------|------|
| 新建 | `jumao new` | 建文件夹 + 起步产品文件。 |
| 访谈 | `jumao interview` | 用普通话记下目标与边界。 |
| 检查 | `jumao check --strict` | 关键产品文件在且非空。 |
| 审计 | `jumao audit --write` | 写代码前的缺口 / 风险说明（`governance/`）。 |
| 打包 | `jumao pack --target …` | 生成交给 AI Coding Agent 的任务包。 |

然后在 Agent 里打开**同一文件夹**，粘贴任务包，并限制只做这份包。Agent 做完后，
对**信任的**项目可：

```bash
jumao verify .
jumao verify . --no-run-checks   # 不执行项目测试
```

### 高级诊断

```bash
jumao doctor .           # 交互式白话体检
jumao doctor . --write   # 需要时写入诊断文件
```

`doctor` 用于**更深入的诊断**，**不是**主流程必经步骤。标准打包前的缺口报告请用
`audit`。

### 其他命令

```bash
jumao plan /你的/项目路径
jumao plan /你的/项目路径 --json
jumao plan /你的/项目路径 --force
jumao status .
jumao pack --target claude .
jumao pack --target cursor .
```

## 安全（短）

- 本地规划；规划不调橘猫云端 AI  
- 检查 / 规划默认只读源码  
- 记录在 `.jumao/`；任务包 / 计划在项目文件里  
- 真实用户、付费、商店审核仍须你确认  

目标、证据、范围、审计、任务包、执行边界如何配合：  
**[橘猫如何工作](docs/concepts/how-jumao-works.zh-CN.md)**。

## 文档

| 文档 | 给谁 |
|------|------|
| [开始使用](docs/getting-started.zh-CN.md) | 第一次成功闭环 |
| [橘猫如何工作](docs/concepts/how-jumao-works.zh-CN.md) | 控制层说明 |
| [使用指南](docs/guide.zh-CN.md) | 更多模板 |
| [更新记录](CHANGELOG.md) | 本 Preview |
| [贡献方式](CONTRIBUTING.zh-CN.md) | 参与贡献 |

## 许可证

MIT — [LICENSE](LICENSE)。
