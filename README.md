# Jumao

Jumao is a product workspace for people who have an app, website, or small tool idea and want help from AI.

Before asking AI to code, Jumao helps you write down the practical parts:
who it is for, what the first version should include, what should stay out,
what happens when a screen is empty or broken, what data is involved, and
what proof shows the work is actually done.

Jumao does not call model APIs or touch your API keys. After you fill the
files, you get a task packet you can give to Codex, Claude Code, Cursor,
Gemini CLI, or any AI coding tool you trust.

中文版本: [README.zh-CN.md](README.zh-CN.md)

## 3-minute start

```bash
git clone <your-fork-or-this-repo> jumao
cd jumao
npm install

node bin/jumao.js new "AI Travel Helper" --dir ./work/ai-travel-helper
node bin/jumao.js check ./work/ai-travel-helper
node bin/jumao.js pack ./work/ai-travel-helper
```

Then give `./work/ai-travel-helper/jumao-task-pack.md` to your AI coding tool and start with:

```text
Please read this Jumao AI task packet first. Do not code yet.
Summarize the product goal, first-version scope, gaps, and next smallest safe action.
```

## Who it is for

- You have an app, website, SaaS, AI tool, or small product idea.
- You cannot code, or can only code a little, but want AI to help you keep moving.
- You do not want AI to expand scope, edit risky systems, or pretend work is done.
- You want every step to have proof: tests, screenshots, logs, or human review.

## What it fixes

AI coding projects often go sideways at the start. The idea is still loose, the boundaries are fuzzy, and the AI does not know what it may or may not touch.

- Who is the product for?
- What is in the first version, and what is not?
- What data can be collected, and what must be avoided?
- What are the empty, error, loading, and permission states?
- What counts as real completion?
- Which actions affect users, bills, review, launch, or production data?

Jumao turns those questions into files a person can fill in, then packs them into context an AI coding tool can read.

## Commands

```bash
jumao init [dir]
jumao new <product-name> --dir [dir]
jumao check [dir]
jumao check [dir] --strict
jumao audit [dir]
jumao audit [dir] --write
jumao interview [dir]
jumao interview [dir] --answers answers.json
jumao pack [dir]
```

Without global install, use:

```bash
node bin/jumao.js new "My Product" --dir ./work/my-product
```

| Command | Purpose |
| --- | --- |
| `init` | Put Jumao docs, templates, and a fillable product skeleton into a directory. |
| `new` | Create a product launch workspace. |
| `check` | Verify required files exist. |
| `check --strict` | Gate: fail on placeholders, filler text, and missing core structure. |
| `audit` | Diagnose gaps, why they matter, and the next safe AI task. |
| `audit --write` | Write the diagnosis to `tasks/audit-report.md`. |
| `interview` | Ask questions and fill the core product files. |
| `interview --answers` | Generate non-interactively from `answers.json`; add `--force` to overwrite existing core files. |
| `pack` | Build `jumao-task-pack.md` for an AI coding tool. |

## Generated workspace

`jumao new "AI Travel Helper"` creates:

```text
AGENTS.md
CLAUDE.md
README.zh-CN.md
README.md
product/
  product-brief.zh-CN.md
  product-brief.md
  scope-gate.zh-CN.md
  scope-gate.md
  screen-states.zh-CN.md
  screen-states.md
  data-safety.zh-CN.md
  data-safety.md
proof/
  release-proof.zh-CN.md
  release-proof.md
```

`jumao pack` creates one AI task packet containing the product brief, first-version scope, screen states, data safety notes, and proof file.

## Recommended workflow

1. Run `jumao new`.
2. Fill `product/product-brief.md`.
3. Fill `product/scope-gate.md`.
4. Fill `screen-states` so AI does not build only the happy path.
5. Fill `data-safety` so AI understands data boundaries.
6. Run `jumao check`.
7. Run `jumao pack`.
8. Give the packet to Codex, Claude Code, Cursor, or another AI coding tool.
9. After each round, record tests, screenshots, logs, or human review in `proof/release-proof.md`.

## Working with Codex, Claude, and Cursor

### Codex

Paste `jumao-task-pack.md` into Codex and say:

```text
Do not edit code yet. Read the Jumao task packet and summarize the goal, gaps, risks, and next plan.
Start implementation only after I confirm.
```

### Claude Code

This repo includes [CLAUDE.md](CLAUDE.md). Ask Claude Code to read `AGENTS.md` and the `product/` files first.

### Cursor

Put the `AGENTS.md` rules into your project rules and keep `jumao-task-pack.md` in context. Before each edit, ask Cursor which first-version goal the change serves.

For copyable prompts, see [AI Prompts](docs/prompts.md).

## Complete example

See [examples/ai-note-helper](examples/ai-note-helper). It is a filled example workspace for an AI note helper:

```bash
node bin/jumao.js check examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper
```

The generated task packet looks like this:

```text
# 橘猫 AI 任务包

## product/product-brief.zh-CN.md

The first version proves one thing: after the user enters a messy note,
they can get a copyable title, summary, and three next actions.

## product/scope-gate.zh-CN.md

Explicitly out of scope: login, payments, team collaboration, cloud sync,
and automatic publishing. Actions that affect users, production data,
payments, launch, or external accounts need human confirmation.
```

See the full output in [examples/ai-note-helper/jumao-task-pack.md](examples/ai-note-helper/jumao-task-pack.md).

## Principles

- Let AI ask first, then let AI code.
- No proof, no "done".
- You can build without knowing every technical detail, but AI must not guess about users, money, or launches.
- Any action that affects users, payments, launch, review, or production data needs human confirmation.

## Maintainer release check

Before publishing to GitHub or npm, run:

```bash
npm run check
npm pack --dry-run
git status --short
```

Create the remote repo, push, or publish only after the working tree is clean,
checks pass, and the package contents look right. GitHub repo creation, push,
and npm publish are external actions, so confirm them first.

See the full [publish checklist](docs/publish-checklist.md). To contribute,
read [CONTRIBUTING.md](CONTRIBUTING.md). Security reporting is covered in
[SECURITY.md](SECURITY.md). Release notes live in [CHANGELOG.md](CHANGELOG.md).

## FAQ

### Does Jumao call OpenAI, Claude, or other models?

No. Jumao only creates local files. It does not call model APIs, read API keys, or create model costs.

### Can I use it if I cannot code?

Yes. Jumao helps you explain the product clearly before asking an AI coding tool to continue.

### Does it generate a full app?

No, and it should not promise that. Jumao prepares the product context, boundaries, and proof so AI coding tools have a clearer starting point.

### Why does it care about proof?

AI can say "done" too early. Real projects need tests, screenshots, logs, review states, or human acceptance.

### Can I use it commercially?

Yes. Jumao is MIT licensed.

## License

MIT
