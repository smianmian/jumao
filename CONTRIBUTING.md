# Contributing to Jumao

Thanks for helping make Jumao easier to use.

Jumao is for people who may not code much but still want to turn an idea into a real product. Good changes should make it easier for them to describe the idea, scope, data, and proof clearly.

## What good contributions look like

- Keep language clear enough for someone who does not write code every day.
- Preserve the core flow: idea, scope, screen states, data safety, proof, task packet.
- Do not add direct AI API calls to the CLI.
- Do not add features that require API keys, cloud accounts, payments, or hosted services by default.
- Do not claim launch, review, deployment, or completion without evidence.
- Keep Chinese and English docs in sync when changing user-facing guidance.

## Before opening a pull request

Run:

```bash
node bin/jumao.js --help
npm run check
node bin/jumao.js check examples/ai-note-helper --strict
node bin/jumao.js audit examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper --target codex
npm pack --dry-run
git status --short
```

In the pull request, include:

- What changed.
- Why it helps regular users.
- What was not changed.
- Verification evidence.

## Writing style

- Prefer ordinary words over engineering jargon.
- When a technical word is necessary, explain it once.
- Avoid promising that Jumao can build a full product by itself.
- Keep risky actions explicit: users, production data, payments, launch, review, and external accounts need human confirmation.
