# Roadmap

Jumao grows by making the existing workflow clearer and safer before adding
new surfaces.

## Done in v0.2.0

v0.2.0 completed the first Agent Review Board release.

- Added 44 built-in responsibility agents.
- Added 8 user-facing agent groups.
- Added `jumao doctor --answers`.
- Added plain-language project diagnosis.
- Added governance output files under `governance/`.
- Added Codex agent gates.
- Included Agent Review Board gates in Codex, Claude, and Cursor task packs.
- Added Chinese user-facing agent documentation.
- Kept the release safe: no AI API calls, no hosted service, no automatic
  backend, database, SDK, push, publish, or tag actions.

## v0.2.1 - Docs polish

This release keeps the code stable and improves the open-source front door.

- Polish README pages for non-programmer users.
- Keep English and Chinese setup steps aligned.
- Keep doctor usage visible but simple.
- Make `docs/agents.zh-CN.md` easier to scan.
- Refresh changelog, roadmap, and contribution guidance.
- Do not change CLI behavior.
- Do not add dependencies.
- Do not add new commands.

## v0.3.0 - Start one-step flow

The next product step is a safer first-run experience.

- Explore `jumao start` as a guided path for new users.
- Reuse the existing product files and Agent Review Board.
- Ask life-style product questions instead of technical questions.
- Keep answers local and machine-readable.
- Make the next safe task clear before any coding tool starts.
- Keep all external actions behind human confirmation.

## v0.4.0 - Skill export

After the start flow is stable, Jumao can help users export clearer handoff
material for AI tools.

- Explore exporting reusable tool instructions.
- Keep Codex, Claude, and Cursor task packs compatible.
- Avoid locking users into one AI vendor.
- Keep generated files plain Markdown and JSON where possible.
- Do not require model API keys.
- Do not require a hosted Jumao account.

## Stability Track

- Keep the core flow stable:
  `new -> interview -> check --strict -> audit -> pack --target`.
- Improve plain-language prompts for non-technical builders.
- Add more example workspaces only when they teach a different product risk.
- Tighten strict checks when real users find confusing gaps.
- Keep docs in English and Chinese aligned.

## Later Ideas

- Add optional presets for common product types.
- Add optional exports for AI tool configuration files.
- Add more target-pack formats if users ask for them.

## Still Out of Scope

- No direct AI API calls.
- No API key handling.
- No Web UI.
- No hosted service.
- No autonomous coding agent.
- No automatic npm publishing.
- No automatic git push or tag creation.
