# v0.4 Completion Receipt and Execution Lifecycle Semantics

This document defines how Jumao runs a one-shot Coding Agent session, how the
agent reports completion, and how the harness verifies that report. It is the
design for the `claude/v0.4-completion-protocol` branch, derived from the
audit in `benchmark/results/claude-lifecycle-audit.md`.

## 1. Three independent results

One execution session produces three separate verdicts. They are never
collapsed into a single PASS/FAIL.

```json
{
  "startupResult": "started",
  "deliveryResult": "passed",
  "lifecycleResult": "clean_exit"
}
```

### startupResult — did the agent begin effective work?

- `started` — the event stream shows effective work (a tool item or file
  change), or the agent produced a final message with a legal receipt that
  justifies doing no work (for example: every goal blocked with reasons).
- `startup_failed` — the process ran, but no effective work began and no
  legal receipt justified the inactivity: no tool item and no file change
  before exit, stall, or the startup window elapsing. Waiting on stdin or a
  hung first tool call lands here.
- `environment_failure` — the session could not run at all: spawn error,
  no `thread.started` event, or a fatal auth/network error on stderr.

Recorded startup milestones (timestamps, null when never reached):
`processSpawned`, `threadStarted`, `modelResponseStarted` (first item event),
`firstToolStarted`, `firstToolCompleted`, `effectiveWorkStarted` (first
non-message item event, or first observed file change).

A session that never started effective work is a startup or environment
problem. It is never counted as a Completion Receipt failure, and never as
evidence about plan quality.

### deliveryResult — is the work actually done?

Judged **only from measured evidence**, never from agent claims:

- `passed` — every explicit goal is completed (per changed-file evidence) or
  justifiably blocked; required checks exit 0; no invalid modifications; no
  constraint violations; no unjustified omissions.
- `incomplete` — goals missing without justification, or no work product.
- `failed` — wrong modifications, constraint violations, or real side
  effects.
- `validation_failed` — the receipt materially contradicts measured
  evidence (see §3), or required checks fail.

### lifecycleResult — did the session end correctly?

- `clean_exit` — legal receipt, natural process exit (no signal from the
  harness), no surviving process-group members.
- `completed_but_forced_exit` — legal receipt and finished work, but the
  process (or a group member) had to be cleaned up by the harness.
- `incomplete` — no legal receipt: stall, kill during work, missing or
  invalid receipt.
- `environment_failure` — mirror of startup-level environment failure.

## 2. Completion Receipt

### 2.1 Channel: the receipt is the final message

`codex exec` is single-turn: it ends with a final agent message and then the
process exits by itself. The protocol therefore makes the **final message the
receipt**, captured via `-o <file>`:

- "Stop calling tools after the receipt" holds by construction — nothing can
  follow the final message inside a turn.
- "Exit naturally after the receipt" reduces to the process exiting after
  `turn.completed`, which the harness measures directly (grace window).
- There is exactly one receipt artifact per session; no second channel can
  contradict it.

The execution prompt instructs the agent to end with a single JSON object of
the shape below. Because local user configuration can inject prose around any
message (observed in the audit), the harness extracts the first balanced JSON
object containing the key `"jumaoCompletion"` from the final message; fenced
code blocks and surrounding prose are tolerated. Absence of any parseable
receipt object, or required fields missing or ill-typed, makes the receipt
**illegal** (lifecycle `incomplete`).

### 2.2 Shape

```json
{
  "jumaoCompletion": {
    "status": "completed",
    "goalsCompleted": ["goal:web-entry"],
    "goalsBlocked": [{ "goalId": "goal:x", "reason": "..." }],
    "validation": [{ "command": "npm test", "exitCode": 0 }],
    "productionEffects": false,
    "remainingWork": []
  }
}
```

- `status`: `"completed"` or `"blocked"`.
- `goalsCompleted`: goal IDs the agent believes are done.
- `goalsBlocked`: goal IDs it could not do, each with a real reason
  (string entries are tolerated and normalized).
- `validation`: every verification command it actually ran, with exit codes.
- `productionEffects`: whether it caused any real-world effect.
- `remainingWork`: unfinished items, empty when nothing remains.

## 3. Receipt verification — claims never override evidence

A structurally legal receipt is then cross-checked. Each rule compares a
claim to independent measurement; any violation marks the receipt
**untruthful** and forces `deliveryResult: validation_failed` (the lifecycle
verdict keeps its own value — a truthful exit and an untruthful claim are
different failures):

1. **Goal claims vs. changed files** — a goal in `goalsCompleted` with no
   matching changed-file evidence (the frozen goal patterns) is a false
   completion claim.
2. **Validation claims vs. re-run checks** — the harness re-runs the project
   checks itself. A receipt claiming `exitCode: 0` for a check the harness
   measures as non-zero is a false validation claim.
3. **`productionEffects: false` vs. scanner** — if
   `detectRealSideEffects()` finds a real side effect in the changed files,
   the scanner wins.
4. **`remainingWork: []` vs. omissions** — an empty remaining-work list
   while measured, unjustified goal omissions exist is a false claim.
5. **Unknown goal IDs** — claiming goals that were never in the handoff.

The receipt adds information (what the agent believes it did); it never
substitutes for the harness's own delivery measurement, which runs
identically whether or not a receipt exists.

## 4. Session runner

### 4.1 Spawn contract

- `spawn` (async), `detached: true` → the agent owns a fresh process group
  (pgid = child pid).
- `stdio: ['ignore', 'pipe', 'pipe']` — **stdin is closed at spawn**. The
  audit shows `codex exec` waits for stdin EOF whenever stdin is an open
  pipe; the protocol forbids ever handing the agent an open stdin.
- stdout (`--json` JSONL events) and stderr stream **incrementally to files**
  in the per-run evidence directory. Nothing is buffered in memory, so no
  `maxBuffer` kill path exists.

### 4.2 State machine

```
spawned → thread_started → responding → working
        → turn_completed (receipt moment)
        → exited                     (natural, lifecycle clean_exit)
        | forced_cleanup             (grace elapsed or stall/timeout)
```

Transitions are driven by the event stream (`thread.started`, first item
event, first non-message item, `turn.completed`) and by process exit. Every
transition is timestamped in `timeline.json`.

### 4.3 Timers — activity-based, not one flat timeout

- `startupMs` (default 5 min): from spawn until `thread.started` plus a
  first item event; expiry → startup failure, controlled cleanup.
- `stallMs` (default 15 min): since the **last** event line; a running tool
  (`item.started` without its `item.completed`) is still subject to this cap,
  which equals the longest allowed single check (`xcodebuild test` budget).
  Expiry → stall, controlled cleanup, lifecycle `incomplete`.
- `exitGraceMs` (default 60 s): from `turn.completed` until process exit;
  expiry → forced cleanup, lifecycle `completed_but_forced_exit` when the
  receipt is legal.
- `globalMs` (default 40 min): absolute cap; expiry → controlled cleanup.

Raising a timer is never a fix for a hang; timers exist to classify and
preserve evidence, and stall detection is based on activity, not total
duration.

### 4.4 Controlled cleanup — group-scoped, never wider

1. Verify the guard `pgid === child.pid` (the group the session itself
   created). The harness only ever signals `-pgid`; it has no code path that
   signals any other pid or group, so unrelated Node/npm/xcodebuild/system
   processes cannot be hit.
2. Snapshot the group (`ps -g <pgid>`) into the evidence directory.
3. `kill(-pgid, SIGTERM)` → wait `termGraceMs` (default 10 s) →
   `kill(-pgid, SIGKILL)` if members survive.
4. Verify extinction (`pgrep -g <pgid>` empty); record every signal sent,
   every survivor found, and the final state in `timeline.json`.
5. `ESRCH` (already gone) is recorded as a no-op, not an error, and never
   triggers a retry against a reused pid.

After a **natural** exit the same group check runs once: survivors mean the
agent leaked children; they are cleaned up and recorded, and lifecycle
becomes `completed_but_forced_exit` at best.

### 4.5 Evidence directory (survives the temp worktree)

Per run, under the results root:
`events.jsonl`, `stderr.log`, `final-message.txt`, `receipt.json` (parsed) or
`receipt-error.txt`, `timeline.json` (milestones, timers fired, signals,
survivors, exit code/signal, durations including receipt→exit), and the
process-group snapshot when cleanup ran. The run JSON links to these files.

## 5. Interaction with execution handoff semantics

The receipt protocol adds no authorization. `prepare`/`validate` stay
authorized by the session context; `execute` stays blocked exactly as defined
in `V0_4_EXECUTION_HANDOFF_SEMANTICS.md`. `productionEffects` in the receipt
is a report, not a permission, and §3 rule 3 makes the scanner authoritative.
Nothing from the receipt is ever written back into project manifests.

## 6. Acceptance (frozen before any real run)

Product gates and lifecycle gates are those of the task definition: SaaS ≥
2/3, Health ≥ 2/3 with real `xcodebuild test` 0, CLI 3/3, adversarial 8/8,
scanner no regression, no production effects; receipts 9/9 legal, no run
waiting on user input, no harness-caused early termination, ≥ 8/9 natural
exits, 0/9 residual processes, ≤ 1/9 forced exits after completion, 0/9
unknown classifications, 0/9 lost evidence. Reported rates:
`startupReliability`, `deliverySuccessRate`, `cleanCompletionRate`,
`endToEndSuccessRate` (startup failures stay in the denominator).
