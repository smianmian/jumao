# Changelog

## 0.1.0 - Release Candidate

First public candidate for Jumao, an agent-ready project governance CLI for AI coding tools.

### Added

- Added the core CLI flow: `new -> interview -> check --strict -> audit -> pack --target`.
- Added `init` and `new` for creating local product workspaces.
- Added `check` for required-file checks.
- Added `check --strict` for blocking empty templates, placeholders, filler text,
  empty structures, and missing core product context.
- Added `audit` and `audit --write` for gap reports and next safe AI tasks.
- Added `interview` and `interview --answers` for filling core product files without starting from blank Markdown.
- Added `pack --target codex|claude|cursor` for tool-specific task packs.
- Added bilingual templates for product brief, scope gate, screen states, data safety, and release proof.
- Added `AGENTS.md` and `CLAUDE.md` handoff files.
- Added the filled `examples/ai-note-helper` workspace and `answers.json` quickstart fixture.
- Added bilingual docs, prompts, publishing checklist, contribution guide,
  security notes, and GitHub issue/PR templates.

### Notes

- Jumao does not call model APIs.
- Jumao does not require API keys.
- Jumao does not publish to npm, push to remote repositories, or create git tags by itself.
