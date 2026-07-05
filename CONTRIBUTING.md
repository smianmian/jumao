# Contributing to Jumao

Thanks for helping make Jumao more useful for non-technical builders.

Jumao is not a code-generation promise. It is a plain-language framework that helps people turn product ideas into clear AI-agent tasks, with scope, safety, and proof.

## What good contributions look like

- Keep language simple enough for a non-technical user.
- Preserve the core flow: idea, scope, screen states, data safety, proof, task packet.
- Do not add direct AI API calls to the CLI.
- Do not add features that require API keys, cloud accounts, payments, or hosted services by default.
- Do not claim launch, review, deployment, or completion without evidence.
- Keep Chinese and English docs in sync when changing user-facing guidance.

## Before opening a pull request

Run:

```bash
npm run check
npm pack --dry-run
git status --short
```

In the pull request, include:

- What changed.
- Why it helps non-technical builders.
- What was not changed.
- Verification evidence.

## Writing style

- Prefer ordinary words over engineering jargon.
- When a technical word is necessary, explain it once.
- Avoid promising that Jumao can build a full product by itself.
- Keep risky actions explicit: users, production data, payments, launch, review, and external accounts need human confirmation.
