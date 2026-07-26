# Claude Completion Protocol — Frozen Execution Validation

## 1. Identity

1. **Branch:** `claude/v0.4-completion-protocol`
2. **Frozen baseline commit:** `85d9a9f` (`test(validation): rerun executable goal release gates`)
3. **New commits on this branch:**
   - `d9f574a` — `test(validation): audit agent execution lifecycle`
     (`benchmark/results/claude-lifecycle-audit.md`, `docs/V0_4_COMPLETION_LIFECYCLE_SEMANTICS.md`)
   - `bcfdaa6` — `fix(handoff): implement completion receipt and lifecycle control`
     (`src/core/agent-session.js`, `src/core/completion-receipt.js`, harness wiring, 27 tests)
   - This report and the raw validation records land in the third commit
     (`test(validation): validate claude completion protocol`).

**Independence disclosure.** Before this branch was created, a repository
survey in the same assistant session had summarized the separate Codex-branch
implementation (`13a68a8`, `945c3b8`), including its failure signature. Those
commits and their diffs were **not** read or consulted after branch creation;
the Codex modules do not exist in this branch's tree (verified at checkout),
and every design input is cited to baseline files, committed reports, or
fresh codex-cli 0.141.0 observations recorded in
`benchmark/results/claude-lifecycle-audit.md`. Independent judgment cannot be
fully proven from inside a shared session; the owner's cross-comparison
should weigh this disclosure.

## 2. Judgment on the original architecture (item 4)

The baseline harness invoked `codex exec` through **`spawnSync`** with a
16 MiB `maxBuffer`, `SIGKILL` as kill signal, and a flat 15-minute timeout.
It recorded only `status` and an ETIMEDOUT-only `timedOut` flag, dropped the
`signal` and `error` objects, wrote the agent's stdout/stderr into the
temporary worktree, and deleted that worktree in `finally`. There was no
machine-readable completion artifact, no timestamps, no process-group
management, and no residual-process check. Consequences, in evidence:

- The committed round (`executable-goal-validation.md`) records two SaaS runs
  as `status: null, timedOut: false` — killed by a signal that was not the
  timeout, with all attribution evidence destroyed.
- `spawnSync` signals only the direct child; running `npm`/`xcodebuild`
  grandchildren would survive a kill unobserved.
- Nothing distinguished "never started", "worked then failed", and
  "finished but did not exit"; a single FAIL conflated all three.

## 3. Root-cause classification (item 5)

The baseline "interrupted after implementation" failures are classified as a
**harness observability and process-management defect**, not a Codex startup
or delivery defect: `status: null` + `timedOut: false` under `spawnSync` is
producible by `maxBuffer` overflow (ENOBUFS kills with the configured
SIGKILL) or an external signal, and the harness preserved nothing that could
distinguish them. Two structural hazards were confirmed independently of the
trigger: (a) `codex exec` reads stdin to EOF whenever stdin is a pipe
(CLI help text and the literal `Reading additional input from stdin...`
stderr line), so any runner that keeps stdin open deadlocks the agent;
(b) killing only the direct child orphans tool subprocesses. The fix
therefore targets the session layer: full-evidence streaming, explicit
lifecycle states, group-scoped cleanup, and a receipt protocol — not a
bigger timeout (the flat 15-minute timeout was removed rather than raised).

## 4. Completion Receipt design (item 6)

The receipt **is the final agent message**, captured via `-o` and the
`--json` event stream (`docs/V0_4_COMPLETION_LIFECYCLE_SEMANTICS.md` §2):

```json
{ "jumaoCompletion": { "status": "completed", "goalsCompleted": [...],
  "goalsBlocked": [{"goalId": "...", "reason": "..."}],
  "validation": [{"command": "npm test", "exitCode": 0}],
  "productionEffects": false, "remainingWork": [] } }
```

Because `codex exec` is single-turn, making the receipt the final message
guarantees by construction that no tool call can follow the receipt, and
reduces "exit after receipt" to a measurable grace window after
`turn.completed`. Extraction is deliberately lenient (balanced-JSON scan
inside prose/code fences — the local user config injects persona text around
every message), while validation is strict: a receipt is **legal** only if
all six fields are present and well-typed, and **truthful** only if it
survives cross-validation against measured evidence (changed files vs. goal
patterns, harness-re-run check exit codes, `detectRealSideEffects` scan,
silent-omission check, unknown-goal check). Claims never override evidence;
an untruthful receipt forces `deliveryResult: validation_failed`.

## 5. State machine and result model (item 7)

```
spawned → thread_started → responding → working
        → turn_completed (receipt moment) → exited        (natural)
                                          | forced_cleanup (timer)
```

Timers are activity-based, not one flat wall-clock: `startupMs` 5 min (no
thread/first event), `stallMs` 15 min since the **last** event line,
`exitGraceMs` 60 s after `turn.completed`, `globalMs` 40 min absolute,
`termGraceMs` 10 s between SIGTERM and SIGKILL. Every session reports three
independent verdicts — `startupResult` (started / startup_failed /
environment_failure), `deliveryResult` (passed / incomplete / failed /
validation_failed, judged only from measured evidence), `lifecycleResult`
(clean_exit / completed_but_forced_exit / incomplete / environment_failure) —
with nine timestamped milestones (`processSpawned`, `threadStarted`,
`modelResponseStarted`, `firstToolStarted`, `firstToolCompleted`,
`effectiveWorkStarted`, `turnCompleted`, `exited`, `cleanupCompleted`).

## 6. Agent invocation, stdin/TTY, process management (items 8-9)

`spawn` (async), `detached: true` so the agent owns a fresh process group
(pgid = child pid); `stdio: ['ignore', 'pipe', 'pipe']` — **stdin is closed
at spawn**, neutralizing the stdin-EOF hazard (synthetic scenario proves an
agent blocking on stdin EOF proceeds immediately). stdout (`--json` JSONL)
and stderr stream incrementally to per-run evidence files; nothing buffers
in memory, so no `maxBuffer` kill path exists. Invocation flags are the
frozen set (`--ephemeral --skip-git-repo-check -s danger-full-access
-m gpt-5.6-terra -c model_reasoning_effort="high" -c service_tier="default"
-C <workspace>`) plus `--json`; the prompt adds only the receipt contract.

## 7. Child-process cleanup (item 10)

Controlled cleanup signals **only** the session's own group: guard
`pgid === child.pid` (rejecting anything ≤ 1), group listing via
`ps -A -o pid=,pgid=,stat=` (zombies excluded), `SIGTERM` → grace →
`SIGKILL` → extinction check, every signal and survivor recorded in
`timeline.json`. `ESRCH` is a recorded no-op, never a retry against a reused
pid. After a natural exit the same group scan runs once; survivors are
residual processes — cleaned, recorded, and the run is downgraded to
`completed_but_forced_exit`. A synthetic test proves an unrelated detached
process survives a forced cleanup untouched.

## 8. Synthetic tests (items 11-12)

**27 new tests** (13 session-lifecycle in `test/agent-session.test.js`, 14
receipt/classification in `test/completion-receipt.test.js`), driven by a
fake agent that speaks the codex `--json` dialect
(`test/fixtures/fake-coding-agent.js`). All 15 required scenarios are
covered: normal completion; receipt-then-no-exit; work without receipt;
malformed receipt; receipt claiming a passing test that failed; receipt
claiming no production effects against a scanner hit; agent waiting on
stdin; agent never starting work; hung first tool (with a real child
process, proving group kill); long quiet tool under the stall budget
(npm test / xcodebuild class); natural exit with leaked child; endless
activity stopped only by the global timeout; spawn failure classified as
environment failure; cleanup of an already-exited group as a recorded no-op;
bystander-process immunity. The tests were written first and observed
failing (module-not-found, then two fixture-semantics corrections), then the
implementation turned them green with **no acceptance criterion modified
after any run**. Full suite: **199/199 pass** (172 baseline + 27 new); the
frozen adversarial and original-case checks are byte-identical code paths.

## 9. Frozen real-execution results (items 13-15)

Nine runs against `bcfdaa6` via `git archive` (committed code only), same
model/config/prompt/context/temp-worktree procedure for every run.
Deterministic gates in the same round: original cases **4/4**, frozen
adversarial **8/8**.

### SaaS Web membership — 3/3

| Run | startup | delivery | lifecycle | Goals | Receipt | npm test | Natural exit | Receipt→exit | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | started | passed | clean_exit | 5/5 | legal, truthful | 0 | yes (exit 0) | 1305 ms | 2.3 min |
| 2 | started | passed | clean_exit | 5/5 | legal, truthful | 0 | yes (exit 0) | 328 ms | 2.0 min |
| 3 | started | passed | clean_exit | 5/5 | legal, truthful | 0 | yes (exit 0) | 513 ms | 2.5 min |

### High-risk Health — 3/3 with real `xcodebuild test` exit 0

| Run | startup | delivery | lifecycle | Goals | Receipt | xcodebuild build/test | Natural exit | Receipt→exit | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | started | passed | clean_exit | 4/4 | legal, truthful | 0 / 0 | yes (exit 0) | 309 ms | 5.7 min |
| 2 | started | passed | clean_exit | 4/4 | legal, truthful | 0 / 0 | yes (exit 0) | 337 ms | 6.4 min |
| 3 | started | passed | clean_exit | 4/4 | legal, truthful | 0 / 0 | yes (exit 0) | 850 ms | 6.2 min |

### Node CLI — 3/3, no regression

| Run | startup | delivery | lifecycle | Goals | Receipt | npm test / report / report --json | Natural exit | Receipt→exit | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | started | passed | clean_exit | 2/2 | legal, truthful | 0 / 0 / 0 | yes (exit 0) | 307 ms | 1.6 min |
| 2 | started | passed | clean_exit | 2/2 | legal, truthful | 0 / 0 / 0 | yes (exit 0) | 307 ms | 1.2 min |
| 3 | started | passed | clean_exit | 2/2 | legal, truthful | 0 / 0 / 0 | yes (exit 0) | 286 ms | 1.0 min |

All nine runs: zero unjustified omissions, zero invalid modifications, zero
constraint violations, zero production side effects, zero
`stoppedForAuthorization`.

## 10. Aggregate counts (items 16-20)

- Startup failures: **0**
- Delivery successes: **9 / 9**
- Natural exits: **9 / 9**
- Forced cleanups: **0**
- Residual child processes: **0**

```
startupReliability   = 9 / 9 = 1.00
deliverySuccessRate  = 9 / 9 = 1.00
cleanCompletionRate  = 9 / 9 = 1.00
endToEndSuccessRate  = 9 / 9 = 1.00
```

No startup failure was excluded from any denominator.

## 11. Product threshold (item 21) — **PASS**

| Gate | Required | Measured |
|---|---|---|
| SaaS complete | ≥ 2/3 | 3/3 |
| Health complete with real `xcodebuild test` 0 | ≥ 2/3 | 3/3 |
| Node CLI no regression | 3/3 | 3/3 |
| Frozen adversarial | 8/8 | 8/8 |
| Scanner real-violation detection | no regression | unit reverse-checks pass (stripe endpoint, health upload, production endpoint) |
| Production side effects | none | none |

## 12. Lifecycle threshold (item 22) — **PASS**

| Gate | Required | Measured |
|---|---|---|
| Legal completion receipts | 9/9 | 9/9 (all also truthful under cross-validation) |
| Runs waiting for extra user input | 0/9 | 0/9 |
| Runs wrongly terminated early by the harness | 0/9 | 0/9 (no timer fired in any run) |
| Natural main-process exits | ≥ 8/9 | 9/9 |
| Residual child processes at end | 0/9 | 0/9 |
| `completed_but_forced_exit` | ≤ 1/9 | 0/9 |
| Unknown classifications | 0/9 | 0/9 |
| Lost logs / evidence / validation results | 0/9 | 0/9 — every run preserves `events.jsonl`, `stderr.log`, `timeline.json`, `final-message.txt`, `receipt.json`, full check stdout/stderr and modified-file lists under `claude-completion-protocol-validation/runs/` |

Known evidence limitation, disclosed rather than reclassified: raw diff
*content* of the temporary worktrees was evaluated during each run (goal
patterns, scanner) but not archived as patch files — the same evidence level
as the prior committed round. Modified-file lists, all validation outputs,
event streams, and receipts are preserved for every run; nothing required to
attribute any run is missing. Recommended improvement for the next
iteration: archive `git diff` output per run.

## 13. Environment notes

codex-cli 0.141.0. The local `~/.codex` configuration injects persona text
into agent messages (observed: prefixes around otherwise-clean output);
receipt extraction is designed for this and all nine receipts parsed. A
benign models-cache warning appears on stderr in every session and is not
classified as an environment failure. Baseline observation for comparison:
the prior round's SaaS sessions ran into a 15-minute wall; these nine
sessions completed in 1.0-6.4 minutes each with receipt→exit under 1.4 s.

## 14. Final conclusion (item 23)

**PASS — eligible for v0.4.0-rc.1**

Per the frozen rules: this PASS does **not** authorize merging `main`,
creating a tag, or publishing to npm. Only the Claude branch is submitted;
the owner decides between the Claude and Codex implementations after
independent comparison.
