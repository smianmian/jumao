# Changelog

## 0.3.0 - Unreleased

### Added

- Add the Jumao Cat macOS menu bar app.
- Add read-only project inspection with `inspect`.
- Distinguish new projects from existing projects.
- Show grouped Agent status and project readiness.
- Add the native interview window with draft recovery.
- Bundle the Jumao CLI and Node runtime for standalone use.
- Add Developer ID signing and Apple notarization support.

## 0.2.4 - Unreleased

### Added

- Add Jumao mascot assets under `assets/jumao/`.
- Include terminal ASCII, color SVG/PNG, template SVG, and state variants in the
  npm package for README, website, npm page, release, and future UI use.

### Safety

- No CLI behavior changes.
- No Mac menu bar app.
- No Codex plugin.
- No automatic publish, push, or tag actions.

## 0.2.3 - Unreleased

### Added

- Add Jumao Cat status system.
- Add `.jumao/status.json` as a local status summary for future UI surfaces.
- Add `jumao status <dir>` for terminal status checks.
- Update `doctor --write` and `pack --target` to write Jumao Cat status.

### Safety

- No AI API calls.
- No Mac menu bar app yet.
- No Codex plugin yet.
- No Web UI.
- No network calls.
- No automatic clipboard writes.
- No assets included in this release.

## 0.2.2 - Unreleased

### Changed

- Add a clear README entry point to the built-in Agent documentation.
- Keep the full 44-agent explanation in `docs/agents.zh-CN.md` instead of
  duplicating it in the README pages.
- Bump package metadata for the docs hotfix release.

### No code changes

- No source code changes.
- No CLI behavior changes.
- No dependency changes.

### Safety

- No npm publish.
- No git tag.
- No push to main.

## 0.2.1 - Released

### Changed

- Polish the public README pages and Chinese user-facing docs.
- Restore readable multi-line Markdown for project pages.
- Clarify that v0.2.0 delivered the Agent Review Board, doctor command, and
  governance gates.
- Refresh roadmap and contribution guidance for the next documentation release.

### No code changes

- No CLI behavior changes.
- No dependency changes.
- No new commands.

### Safety

- No npm publish.
- No git tag.
- No push to main.

## 0.2.0 - Released

### Added

- Add Agent Review Board with 44 built-in responsibility agents.
- Add `jumao doctor --answers` for plain-language project diagnosis.
- Add governance output files under `governance/`.
- Include Agent Review Board gates in Codex, Claude, and Cursor task packs.
- Add Chinese user-facing agent documentation.

### Safety

- No AI API calls.
- No automatic backend, database, SDK, push, publish, or tag actions.

## 0.1.1 - Unreleased

### Changed

- Improve beginner-friendly install, uninstall, and Codex usage instructions.

### No code changes

- No CLI behavior changes.
- No dependency changes.

## 0.1.0 - Release Candidate

First public candidate for Jumao, an agent-ready project governance CLI for AI
coding tools.

### Added

- Added the core CLI flow:
  `new -> interview -> check --strict -> audit -> pack --target`.
- Added `init` and `new` for creating local product workspaces.
- Added `check` for required-file checks.
- Added `check --strict` for blocking empty templates, placeholders, filler text,
  empty structures, and missing core product context.
- Added `audit` and `audit --write` for gap reports and next safe AI tasks.
- Added `interview` and `interview --answers` for filling core product files
  without starting from blank Markdown.
- Added `pack --target codex|claude|cursor` for tool-specific task packs.
- Added bilingual templates for product brief, scope gate, screen states,
  data safety, and release proof.
- Added `AGENTS.md` and `CLAUDE.md` handoff files.
- Added the filled `examples/ai-note-helper` workspace and `answers.json`
  quickstart fixture.
- Added bilingual docs, prompts, publishing checklist, contribution guide,
  security notes, and GitHub issue/PR templates.

### Notes

- Jumao does not call model APIs.
- Jumao does not require API keys.
- Jumao does not publish to npm, push to remote repositories, or create git tags
  by itself.
