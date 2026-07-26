# v0.4 Agent Assessment Semantics

## Purpose

An Agent's execution status says whether it completed an assessment. It does not
say whether the assessment changed the development plan.

## Execution status

- `completed`: the Agent reached a safe assessment conclusion.
- `blocked`: evidence is insufficient or contradictory, the scope is ambiguous,
  or a required human confirmation is missing.
- `skipped`: the role is not applicable, or it has no positive trigger evidence.
- `failed`: the runtime or a required tool failed.

`assessed_no_change` is deliberately not an execution status.

## Assessment outcome

Completed Agent output carries `assessmentOutcome`:

- `changed_plan`: reliable evidence and an independent finding changed the plan.
  It requires a generated task or protected constraint, plan contribution, and
  decision impact.
- `no_change`: reliable evidence and an independent finding show that the
  existing plan is sufficient. It must not invent a task, constraint, plan
  contribution, or decision impact.

## Safety gate

Before role analysis, the runtime blocks roles affected by insufficient evidence,
contradictory constraints, ambiguous negation scope, or irreversible work without
backup, rollback, verification, and human confirmation. A blocked role never
creates a priority task.

## Scope

Evidence and plan contributions carry the smallest known path scope. A constraint
from `packages/a/` applies only there unless the input explicitly declares it
global. Merged tasks require the same goal, protection boundary, and scope.
