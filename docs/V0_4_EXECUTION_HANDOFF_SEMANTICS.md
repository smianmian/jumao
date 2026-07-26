# v0.4 Execution Handoff Semantics

## Purpose

Planning must distinguish implementing a safe capability from causing a real
production effect. A request to implement the current plan authorizes local
implementation and validation only within the current handoff scope.

## Execution phases

- `prepare`: write code, configuration, tests, migration scripts, backup logic,
  rollback logic, permission flows, and deletion flows.
- `validate`: run tests, builds, local simulations, or isolated-worktree checks.
- `execute`: affect real accounts, real data, production environments, or
  external services.

## Authorization

An explicit request to implement the supplied plan authorizes `prepare` and
`validate` inside the current, named scope. Ordinary local code changes do not
need repeated owner confirmation. Writing code for a dangerous operation is not
the same as executing that operation.

Without a separate, current-session authorization, `execute` remains blocked
for production databases, real migrations, destructive real-data operations,
production authentication changes, production releases, real user health data,
real payments, and paid external services.

Authorization is temporary. Words such as “continue”, “execute”, or “start” are
not durable global approval. Authorization applies only to the current session,
declared scope, and declared phase. It must not be stored as `ownerConfirmed` or
another reusable approval flag in a project manifest.

## Safe preparation for irreversible work

Missing production authorization must not block preparation. A migration may
still produce a design, backup implementation, migration script, rollback
implementation, and test-data validation. The plan must separately state that
the real production migration remains blocked.

HealthKit preparation may include permission declarations, the smallest
authorization request, refusal state, local simulated data, local deletion,
non-diagnostic copy, and tests. It must not read or upload real user health data
or enable production synchronization without explicit execute authorization.

## Goal coverage

The handoff extracts only goals explicitly stated by the user. Each required
goal receives a stable ID. Every goal must be covered by at least one final
priority task or have a concrete blocking reason. Missing coverage blocks the
handoff; it must never be silently passed to Codex. Explicit login does not
imply membership, payment, or another unstated goal.

## Ephemeral execution context

An execution harness may pass this session-only context to Codex:

```json
{
  "executionMode": "sandbox_implementation",
  "authorizedScope": ["current temporary worktree"],
  "allowPrepare": true,
  "allowValidate": true,
  "allowProductionEffects": false
}
```

It is an execution input, not project evidence, a manifest field, or permanent
user authorization.
