# Security Policy

Jumao runs locally and mainly creates docs and task packets. By default, it does not call AI APIs, read API keys, store secrets, or connect to hosted services.

## Supported versions

The current `main` branch and latest tagged release are supported.

## Reporting a security issue

Please do not open a public issue for a security problem.

If the repository is hosted on GitHub, use GitHub private vulnerability reporting when available. If it is not available yet, contact the maintainer privately through the account that owns the repository.

Include:

- What happened.
- A minimal reproduction if possible.
- Whether secrets, user data, payment data, production data, or external accounts are involved.
- Any logs or screenshots that do not expose secrets.

## Scope

Security-sensitive issues include:

- Accidental reading or writing of API keys, tokens, or `.env` files.
- CLI behavior that sends data to a network service without explicit user action.
- Generated guidance that tells an AI coding tool to touch production data, payments, launches, reviews, or external accounts without confirmation.
- Package contents that accidentally include secrets or private project files.

## Out of scope

- Requests to add direct AI API calls to Jumao.
- Issues in a separate app built using Jumao.
- Publicly sharing secrets and then asking maintainers to clean them from third-party systems.

## Maintainer checklist

Before publishing, run:

```bash
npm run check
npm pack --dry-run
git status --short
```

Review the package output and confirm it does not include secrets, local work directories, or private evidence.
