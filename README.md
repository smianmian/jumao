# Jumao Cat

[简体中文](README.zh-CN.md)

Jumao Cat turns a new product idea or one change to an existing project into an
evidence-backed development plan that you can hand to Codex. It plans locally;
it does not write application source code or publish anything for you.

<img src="docs/images/jumao-cat/jumao-cat-overview.png" alt="Jumao Cat project selection and planning panel" width="280">

## Download Jumao Cat

[**Download Jumao Cat for macOS**](https://github.com/smianmian/jumao/releases/latest)

Current support:

- macOS 14 or later on Apple silicon (arm64)
- Published downloads are Developer ID signed and Apple notarized
- No system Node.js, Homebrew, npm, or global Jumao installation is required
- A Node CLI is also available for terminal workflows

Download the ZIP, unzip it, move `Jumao Cat.app` to Applications, and open it
from Applications.

## The normal Jumao Cat flow

1. Choose a new-project folder or an existing code project.
2. For a new project, answer three plain-language questions: what you want to
   make, what it should do, and where you want to use it first.
3. For an existing project, describe only what you want this change to become.
   Jumao Cat inspects visible project evidence instead of asking you to repeat
   facts it can already see.
4. Confirm Jumao Cat's understanding. The app then runs the local Agent Planning
   Runtime automatically.
5. Review the real results from 8 groups and 44 professional roles, including
   which roles completed, were skipped, were blocked, or failed.
6. Review the generated Codex-ready development plan.
7. Click **Hand to Codex**, open the same project folder in Codex, and paste the
   copied instruction.

<img src="docs/images/jumao-cat/jumao-cat-new-project.png" alt="Jumao Cat focused new-project intake" width="640">

Jumao Cat restores unfinished intake drafts and the latest planning run. You can
also rerun planning when the project or request changes.

## What the Agent Planning Runtime is

Agent Planning Runtime v1 is a **local deterministic rules pipeline**. It does
not call an external AI API.

The 44 Agents are auditable professional review roles grouped into 8 areas.
They are not 44 independent large models developing in parallel. Each role gets
a real runtime result:

- `completed`: relevant evidence was found and the role produced analysis
- `skipped`: no relevant trigger or project evidence was found
- `blocked`: a required decision or input is missing
- `failed`: the role or output step could not complete

Results come from the user's answers, read-only project inspection, and evidence
found in the selected project. Affected-file location is deliberately
conservative evidence matching; it is not a complete source-code dependency
graph.

## Files and safety

- Project source code is read-only by default during inspection and planning.
- Planning runs, manifests, evidence, and latest-run state are written under
  `.jumao/`.
- The main handoff document is `tasks/jumao-agent-plan.md`.
- Jumao Cat does not call external AI APIs, add application code, publish,
  charge users, or make release decisions.

## Node CLI

The same planning runtime is available from the terminal:

```bash
npm install -g jumao
jumao plan /path/to/project
```

Machine-readable and rerun modes are available when needed:

```bash
jumao plan /path/to/project --json
jumao plan /path/to/project --events-jsonl
jumao plan /path/to/project --force
```

The existing `new`, `interview`, `inspect`, `check`, `audit`, `doctor`, `pack`,
and `status` commands remain available. There are no breaking CLI changes in
v0.3.1.

## Documentation

- [Guide](docs/guide.md)
- [Agent guide](docs/agents.zh-CN.md)
- [Publishing checklist](docs/publish-checklist.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
