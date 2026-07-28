# Jumao Cat · 橘猫

[简体中文](README.zh-CN.md)

**Public Preview · [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

## What is Jumao?

**Jumao helps people who do not write code finish an app journey with AI — from
idea toward something they can really ship.**

You describe what you want in everyday language. Jumao turns that into a clear
plan and task package. You hand the package to an **AI coding agent** (for
example Codex, Claude Code, or Cursor). The agent writes the code; you stay in
charge of what “done” means, what this version must not do, and anything that
touches real users, money, or publish.

Under the hood, Jumao is the **decision and delivery control layer** for AI
coding agents: it fixes goals, boundaries, and proof *before* the agent starts
editing files — and can check the agent’s “I finished” story afterward.

Jumao runs **on your own computer**. Planning does not call a Jumao cloud AI API.
It does not silently publish your app or charge end users for you.

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat" width="280">

## Why it exists

AI writes code **fast**. Without a fixed first version, it also:

- invents features you never asked for  
- skips “what we are **not** building yet”  
- says “done” without proof  

Jumao is the step **before** coding so the agent gets a smaller, checkable job.

## The path: idea → ship

This is the product path every user should see first:

```text
  Idea
    → Jumao understands you
    → Jumao produces a plan / task package
    → AI coding agent develops in the same folder
    → Verify, then you decide launch
```

| Stage | What happens |
|-------|----------------|
| **Idea** | You know what you want (or what to change), even roughly. |
| **Jumao understands** | Plain questions + what it can see in your project folder. |
| **Plan / package** | A readable plan and a packet the agent can follow. |
| **AI develops** | Codex, Claude Code, Cursor, etc. implement **that** packet in the same folder. |
| **Verify & launch** | Optional check of the agent’s completion story; **you** still decide store / real users / money. |

**Prefer a Mac app?** Download
[**Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2),
pick a folder, answer a few questions, review the plan, then **Hand to AI Coding
Agent** (the copy includes Codex as one example, not the only tool).

Full walkthrough: **[Getting started](docs/getting-started.md)**.

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Plain questions for a new project" width="640">

## Install (v0.4.0-rc.2 Preview)

### Jumao Cat for macOS (recommended for most people)

[**Download Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)

1. Download `JumaoCat-v0.4.0-rc.2-arm64.zip`
2. Unzip → drag `Jumao Cat.app` into **Applications**
3. Open it from **Applications**

Requirements: macOS 14+, Apple silicon (arm64). Signed and notarized. No Node.js
required for the app.

### CLI

```bash
npm install -g jumao@rc
```

Installs Preview **0.4.0-rc.2** via the `rc` dist-tag.

Older tags (for example v0.3.1) stay on GitHub for history only. **New users
start on v0.4.0-rc.2.**

## For developers: CLI workflow

After you know the product path above, the terminal flow is:

```bash
npm install -g jumao@rc

# 1) Create a product workspace
jumao new "My first app" --dir ./my-first-app
cd ./my-first-app

# 2) Plain-language interview
jumao interview .

# 3) Ensure required product files exist and are non-empty
jumao check --strict .

# 4) Structured gap report (main audit path)
jumao audit . --write

# 5) Task packet for an AI coding agent (Codex is one target among others)
jumao pack --target codex .
# also: --target claude | --target cursor
```

| Step | Command | Plain meaning |
|------|---------|----------------|
| New | `jumao new` | Create folder + starter product files. |
| Interview | `jumao interview` | Record goals and boundaries in normal language. |
| Check | `jumao check --strict` | Required product files present and filled. |
| Audit | `jumao audit --write` | Gap / risk notes before coding (`governance/`). |
| Pack | `jumao pack --target …` | Build the handoff packet for your AI coding agent. |

Then open the **same** folder in your agent, paste the packet, and limit work to
that packet. On **trusted** projects after the agent finishes:

```bash
jumao verify .
jumao verify . --no-run-checks   # no project test execution
```

### Advanced diagnostics

```bash
jumao doctor .           # interactive plain-language checkup
jumao doctor . --write   # write diagnosis files when needed
```

`doctor` is for deeper diagnosis. It is **not** required in the main path above;
prefer `audit` for the standard pre-pack gap report.

### Other CLI commands

```bash
jumao plan /path/to/project
jumao plan /path/to/project --json
jumao plan /path/to/project --force
jumao status .
jumao pack --target claude .
jumao pack --target cursor .
```

## Safety (short)

- Local planning; no Jumao cloud AI API for the plan step  
- Project source read-only by default while inspecting / planning  
- Notes under `.jumao/`; packs/plans in project files  
- You still confirm real users, payments, and store review  

How goals, evidence, scope, audit, pack, and execution boundaries fit together:  
**[How Jumao works](docs/concepts/how-jumao-works.md)**.

## Documentation

| Doc | For |
|-----|-----|
| [Getting started](docs/getting-started.md) | First success path |
| [How Jumao works](docs/concepts/how-jumao-works.md) | Control layer (builders) |
| [Guide](docs/guide.md) | Extra product templates |
| [Changelog](CHANGELOG.md) | This Preview |
| [Contributing](CONTRIBUTING.md) | How to help |

## License

MIT — [LICENSE](LICENSE).
