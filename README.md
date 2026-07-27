# Jumao Cat

[简体中文](README.zh-CN.md)

**Current public Preview: [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

Jumao Cat turns a product idea — or one change to an existing project — into an
evidence-backed development plan you can hand to an AI coding agent (Codex,
Claude Code, Cursor, and similar tools).

AI coding tools are fast at writing code and slow at staying inside the right
scope. Jumao plans **locally** first: plain-language intake, read-only project
evidence, and a deterministic review pipeline. It does **not** write application
source code, call external AI APIs, or publish for you.

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat project selection and planning panel" width="280">

## Install (Preview v0.4.0-rc.2)

### Option A — Jumao Cat for macOS (recommended for most people)

[**Download Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)

- macOS 14 or later, Apple silicon (arm64)
- Developer ID signed and Apple notarized
- No system Node.js, Homebrew, npm, or global Jumao required

Download `JumaoCat-v0.4.0-rc.2-arm64.zip`, unzip, move `Jumao Cat.app` to
Applications, then open it from Applications.

### Option B — Node CLI

```bash
npm install -g jumao@rc
jumao plan /path/to/project
```

This installs the current Preview line (`0.4.0-rc.2` via the `rc` dist-tag).

> Older releases such as **v0.3.1** remain available for history and comparison.
> They are **not** the recommended install for new users.

## From idea to AI coding agent

1. **Describe** — new project: what to build, what it should do, where to use it
   first (optional: what this version must not do). Existing project: what this
   change should become.
2. **Plan** — Jumao runs a local Agent Planning Runtime (rules + evidence, no
   model API). You get a real status per professional review role.
3. **Hand off** — open `tasks/jumao-agent-plan.md` (or use **Hand to Codex** in
   the app), open the same folder in your coding agent, paste the instruction.
4. **Check** — after the agent works, it should leave a completion receipt;
   `jumao verify` can independently check claims against evidence (on trusted
   projects).

## The normal Jumao Cat flow

1. Choose a new-project folder or an existing code project.
2. For a new project, answer three plain-language questions — plus one optional
   “what not to do this version” question.
3. For an existing project, describe only the change. Jumao inspects visible
   project evidence instead of re-asking known facts.
4. Confirm understanding. The app runs the local planning runtime.
5. Review results from 8 groups and 44 professional roles (`completed` /
   `skipped` / `blocked` / `failed`).
6. Review the generated, agent-ready development plan.
7. Click **Hand to Codex** (or copy the instruction for Claude Code / Cursor),
   open the same project folder in the agent, and paste.

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Jumao Cat focused new-project intake" width="640">

Jumao Cat restores unfinished intake drafts and the latest planning run. Rerun
planning when the project or request changes.

## What the Agent Planning Runtime is

Agent Planning Runtime v1 is a **local deterministic rules pipeline**. It does
not call an external AI API.

The 44 Agents are auditable professional review roles in 8 groups — not 44
independent large models coding in parallel. Each role gets a real runtime
result: `completed`, `skipped`, `blocked`, or `failed`.

Results come from your answers, read-only project inspection, and evidence in
the selected project. Affected-file hints are conservative evidence matching,
not a full dependency graph.

## Files and safety

- Project source is read-only by default during inspection and planning.
- Runs, manifests, evidence, and latest-run state go under `.jumao/`.
- Main handoff document: `tasks/jumao-agent-plan.md`.
- No external AI APIs, no automatic application coding, no publish, charge, or
  release decisions on your behalf.

## CLI notes

```bash
npm install -g jumao@rc

jumao plan /path/to/project
jumao plan /path/to/project --json
jumao plan /path/to/project --events-jsonl
jumao plan /path/to/project --force
jumao verify /path/to/project
jumao verify /path/to/project --no-run-checks
```

By default, `jumao verify` re-runs the project's own tests (`npm test` and/or
`xcodebuild test`) so false “tests passed” claims can be caught. **Only use full
verify on projects you trust.** Use `--no-run-checks` for static receipt + file
evidence only.

`jumao interview` defaults to the focused questions (`--full` for the long form).
`jumao doctor` without args runs an interactive Chinese checkup. Commands such
as `new`, `inspect`, `check`, `audit`, `pack`, and `status` remain available.

## Documentation

**Start here**

- [Guide](docs/guide.md) — first-run path and product files
- [Changelog](CHANGELOG.md) — what changed in this Preview

**Go deeper**

- [Agent guide (zh-CN)](docs/agents.zh-CN.md)
- [Contributing](CONTRIBUTING.md)
- [Publishing checklist](docs/publish-checklist.md)

## License

MIT — see [LICENSE](LICENSE).
