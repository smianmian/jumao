# Publish Checklist

Use this checklist when publishing Jumao from the local repo to GitHub or npm. Publishing affects external platforms, so confirm before doing it.

## Local checks

```bash
npm run check
npm pack --dry-run
git status --short
```

Confirm:

- `npm run check` passes.
- `npm pack --dry-run` includes the expected files.
- `git status --short` is clean.
- README files do not contain temporary placeholders, old project names, or irrelevant content.
- The example workspace passes `jumao check` and `jumao pack`.

## GitHub publish

Recommended repo name: `jumao`

After confirmation, run:

```bash
gh repo create smianmian/jumao --public --source=. --remote=origin --push
```

After publishing, check:

- The GitHub page opens.
- README renders as the default page.
- The `main` branch contains the latest commit.
- The remote URL is set as `origin`.

## npm publish

The first version does not have to be published to npm. Publish only when you want others to use `npx jumao` or install it globally.

Before publishing, confirm:

- Package name `jumao` is available.
- Version number is correct.
- `npm pack --dry-run` contents are correct.
- You are logged in to the correct npm account.

After confirmation, run:

```bash
npm publish
```

## Do not claim too early

- Do not say "open sourced" before the GitHub repo exists.
- Do not say "published to npm" before npm publish succeeds.
- Do not create a remote repo, push, or publish to npm without user confirmation.
