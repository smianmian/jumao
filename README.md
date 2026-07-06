# Jumao

Jumao is an agent-ready project governance CLI for AI coding tools.

It helps builders avoid handing a vague idea directly to Codex, Claude, or Cursor
and then watching the AI write code in the wrong direction. Jumao turns product
intent, first-version boundaries, screen states, data safety, handoff rules, and
completion proof into files that an AI coding tool can read before it edits code.

Jumao does not call model APIs, does not require API keys, does not write your
app code by itself, does not publish to npm, and does not push to remote
repositories.

中文版本: [README.zh-CN.md](README.zh-CN.md)

## 5-minute Quickstart

Run this from the repo root:

```bash
node bin/jumao.js new "AI Note" --dir ./tmp/ai-note
node bin/jumao.js interview ./tmp/ai-note --answers ./examples/ai-note-helper/answers.json
node bin/jumao.js check ./tmp/ai-note --strict
node bin/jumao.js audit ./tmp/ai-note --write
node bin/jumao.js pack ./tmp/ai-note --target codex
```

The result is a workspace in `./tmp/ai-note` and a Codex-ready task pack at:

```text
./tmp/ai-note/tasks/codex-task-pack.md
```

Give that task pack to your AI coding tool and ask it to summarize the product
goal, first-version scope, risks, and next smallest safe task before editing code.

## Core Flow

```text
new -> interview -> check --strict -> audit -> pack --target codex|claude|cursor
```

| Step | What it proves |
| --- | --- |
| `new` | The product workspace exists. |
| `interview` | The user can fill core product context without staring at blank Markdown. |
| `check --strict` | The context is no longer empty, vague, or placeholder-heavy. |
| `audit` | The user can see gaps, why they matter, and the next safe AI task. |
| `pack --target` | Codex, Claude, or Cursor gets a scoped task pack with tool-specific rules. |

## Who It Is For

- People with an app, website, SaaS, AI tool, or small product idea.
- Builders who do not code much but use Codex, Claude Code, Cursor, or similar
  tools.
- Teams that want AI coding work to start from a product boundary instead of a
  loose chat prompt.
- Maintainers who want every round of AI work to leave tests, screenshots, logs,
  or human review notes.

## What It Helps Prevent

AI coding work often drifts because the tool is missing product context.

- The user is unclear.
- The first version is too broad.
- Excluded features are not written down.
- Empty, error, loading, success, and permission states are missing.
- Data collection and deletion rules are vague.
- The AI says work is done without proof.
- A coding tool touches publishing, production data, payments, or remote
  repositories too early.

Jumao turns those risks into files, checks, reports, and task packs.

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
jumao interview [dir] --answers answers.json --force
jumao pack [dir]
jumao pack [dir] --target codex
jumao pack [dir] --target claude
jumao pack [dir] --target cursor
```

Without global install, use `node bin/jumao.js ...` from this repo.

| Command | Purpose |
| --- | --- |
| `init` | Put Jumao docs, templates, and a fillable product skeleton into a directory. |
| `new` | Create a product workspace. |
| `check` | Verify required files exist. |
| `check --strict` | Gate: fail on placeholders, filler text, empty structures, and missing core product context. |
| `audit` | Diagnose gaps, explain why they matter, and suggest the next safe AI task. |
| `audit --write` | Write the diagnosis to `tasks/audit-report.md`. |
| `interview` | Ask questions and fill the four core product files. |
| `interview --answers` | Generate core files from JSON; add `--force` to overwrite filled files. |
| `pack` | Build the legacy `jumao-task-pack.md`. |
| `pack --target` | Build a Codex, Claude, or Cursor task pack after the strict gate passes. |

## Generated Workspace

`jumao new "AI Note"` creates:

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

`pack --target codex|claude|cursor` also creates a tool-specific file under `tasks/`.

## Working With AI Coding Tools

### Codex

```bash
node bin/jumao.js pack ./tmp/ai-note --target codex
```

The Codex pack reminds the tool to read `AGENTS.md`, keep edits scoped, run tests
before reporting completion, and report changed / not changed / test result /
remaining gaps.

### Claude

```bash
node bin/jumao.js pack ./tmp/ai-note --target claude
```

The Claude pack reminds the tool to read `CLAUDE.md`, keep implementation
scoped, and explain assumptions before large changes.

### Cursor

```bash
node bin/jumao.js pack ./tmp/ai-note --target cursor
```

The Cursor pack reminds the tool to keep edits small, prefer the existing
project structure, and avoid new architecture unless asked.

## Complete Example

See [examples/ai-note-helper](examples/ai-note-helper). It is a filled workspace
for a small AI note helper.

```bash
node bin/jumao.js check examples/ai-note-helper --strict
node bin/jumao.js audit examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper --target codex
```

The example answers file used in the quickstart lives at
[examples/ai-note-helper/answers.json](examples/ai-note-helper/answers.json).

## Release Candidate Checks

For the v0.1.0 candidate, run:

```bash
node bin/jumao.js --help
npm test
npm run check
npm pack --dry-run
git status --short
```

Publishing to GitHub, pushing a branch, publishing to npm, or creating a git tag
are external release actions. Do them only after a human confirms.

## Project Files

- [CHANGELOG.md](CHANGELOG.md): release notes.
- [ROADMAP.md](ROADMAP.md): small, scoped next steps.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution rules.
- [SECURITY.md](SECURITY.md): security reporting.
- [docs/guide.md](docs/guide.md): longer guide.
- [docs/prompts.md](docs/prompts.md): copyable AI handoff prompts.
- [docs/publish-checklist.md](docs/publish-checklist.md): publishing checklist.

## FAQ

### Does Jumao call OpenAI, Claude, or other models?

No. Jumao only reads and writes local files. It does not call model APIs, read
API keys, or create model costs.

### Can I use it if I cannot code?

Yes. Jumao is designed to help you explain the product clearly before asking an
AI coding tool to continue.

### Does it generate a full app?

No. Jumao prepares product context, boundaries, task handoff, and proof
structure. A separate AI coding tool or developer still implements the product.

### Can I use it commercially?

Yes. Jumao is MIT licensed.

## License

MIT
