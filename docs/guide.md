# Jumao Guide

**Current public Preview: [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

Jumao helps you sort out the product **before** you ask an AI coding agent to
write code.

**First time here?** Start with [Getting started](getting-started.md), then
[How Jumao works](concepts/how-jumao-works.md). This page is optional depth
(templates and drift checks).

## Recommended path: Jumao Cat (macOS)

For most people, start with the app:

1. Install Preview from the
   [v0.4.0-rc.2 release](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)
   (or install the CLI with `npm install -g jumao@rc`).
2. Pick a new folder or an existing project.
3. Answer the short plain-language questions.
4. Confirm understanding and let local planning run.
5. Hand the plan to an AI coding agent (e.g. Codex, Claude Code, Cursor) and
   paste the instruction in the **same** project folder.

See the main [README](../README.md) for install links and the full app flow.

## Why this exists

AI coding tools move fast. Without a clear first-version goal, boundaries, and
proof, they expand scope, invent features, or claim “done” without evidence.
Jumao is a **local** planning step so the handoff into the agent is smaller and
checkable.

## CLI path (same runtime)

```bash
npm install -g jumao@rc
jumao interview /path/to/project   # focused questions by default
jumao plan /path/to/project
# after the coding agent finishes:
jumao verify /path/to/project      # only on projects you trust
```

The main handoff file is usually `tasks/jumao-agent-plan.md`.

## Optional product files (advanced / templates)

Some workflows still use filled product docs under `product/` and `proof/`
(brief, scope gate, screen states, data safety, release proof). Those remain
useful as **human-readable product records** and for `jumao pack` task packets.
They are **not** required for the focused Jumao Cat / `jumao plan` Preview path.

Copyable prompts for handoff and drift checks live in [AI Prompts](prompts.md).

## How to know the agent is drifting

After each change, ask:

1. Which user goal does this serve?
2. What proof shows it is done?
3. Does it affect real users, money, review, launch, or production data?

If the answer is unclear, stop and clarify.

## Older versions

**v0.3.1** and earlier releases are historical. New users should start on
**v0.4.0-rc.2 Preview** (`jumao@rc` or the macOS Preview build), not the old
stable line.
