# Claude Lifecycle Audit — Agent Execution Harness

Branch: `claude/v0.4-completion-protocol` (frozen baseline `85d9a9f`).

This audit records how the current harness invokes a one-shot Coding Agent,
what the two committed validation rounds actually prove, and which failure
paths remain non-attributable. It was produced before any implementation work
on this branch.

Disclosure: before this branch was created, a repository survey in the same
assistant session summarized the separate Codex-branch implementation
(commits `13a68a8`, `945c3b8`). Those commits and their diffs were not read or
consulted while producing this audit or the design that follows; every claim
below cites baseline files, committed reports, or fresh CLI observations.

## 1. Current invocation architecture (baseline)

`benchmark/run-execution-handoff.js` drives real executions:

- `codexRun()` calls `command()`, which uses **`spawnSync`** with
  `timeout: 900000`, `killSignal: 'SIGKILL'`, `maxBuffer: 16 MiB`
  (`run-execution-handoff.js:49-66,258-270`).
- Invocation: `codex exec --ephemeral --skip-git-repo-check -s
  danger-full-access -m gpt-5.6-terra -c model_reasoning_effort="high" -c
  service_tier="default" -C <workspace> -o codex-final.md <prompt>`.
- The recorded result keeps only `status`, `timedOut`,
  `stoppedForAuthorization`, `commitsAfter`, `finalOutput`
  (`runOne()`, `run-execution-handoff.js:333-339`). The `signal` and the
  `error` object from `spawnSync` are dropped.
- `codex-stdout.log` / `codex-stderr.log` are written **into the temporary
  worktree**, and `main()` removes the whole temp root in `finally`
  (`run-execution-handoff.js:472-474`), so after a run no Agent output
  survives anywhere.
- There is no machine-readable completion artifact: completion is inferred
  from `git status` diffs, regex goal patterns, and re-run project checks.

## 2. What the committed validation rounds prove

### Round 1 — `execution-handoff-validation.md` (FAIL)

Delivery-level failure: three SaaS runs produced no web entry. This was a
planning/handoff gap, fixed before the frozen baseline. Not a lifecycle issue.

### Round 2 — `executable-goal-validation.md` (FAIL)

Delivery succeeded almost everywhere (SaaS 3/3 goals + tests 0, Health 2/3
with real `xcodebuild test` 0, CLI 3/3). The FAIL was purely lifecycle:

> two SaaS Codex processes are recorded as "interrupted after
> implementation" rather than clean exits.

The raw records show the exact signature
(`executable-goal-validation/runs/saas-web-membership/repair-1.json`):

```json
"codex": { "status": null, "timedOut": false }
```

## 3. Failure-path analysis of the `status: null, timedOut: false` signature

With `spawnSync`, `status === null` means the child was terminated by a
signal. The harness records `timedOut` only for `error.code === 'ETIMEDOUT'`.
Three termination mechanisms exist; the record cannot distinguish them:

1. **Timeout** — excluded here (`timedOut: false`).
2. **`maxBuffer` overflow** — `spawnSync` kills the child with `killSignal`
   (SIGKILL) and sets `error.code === 'ENOBUFS'`, `status: null`. A
   ~15-minute high-reasoning `codex exec` streams enough stdout/stderr to
   make the 16 MiB cap a realistic kill path. The harness never records the
   `error` object or `signal`, so this cannot be confirmed or excluded from
   the JSON alone — which is precisely the observability defect.
3. **External signal** — cannot be excluded either, for the same reason.

Additional structural defects, independent of the trigger:

- `spawnSync` signals **only the direct child**. `codex exec` spawns shell
  children (`/bin/zsh -lc ...`, `npm test`, `xcodebuild`). A SIGKILL to the
  parent orphans any running child; nothing verifies or cleans the process
  tree afterward.
- All timing information is lost: no spawn/first-output/exit timestamps, so
  "interrupted after implementation" could not be located in time.
- Logs die with the temp dir; `signal`/`error` are dropped; there is no
  event stream. A failed run therefore preserves **no attributable scene**.

## 4. Fresh CLI observations (codex-cli 0.141.0, recorded 2026-07-26)

Two disposable smoke runs (trivial prompts, scratchpad, not part of any
frozen validation) established the interface facts the design relies on:

- `codex exec --help`: *"If not provided as an argument (or if `-` is used),
  instructions are read from stdin. If stdin is piped and a prompt is also
  provided, stdin is appended as a `<stdin>` block."* stderr confirms:
  `Reading additional input from stdin...`. **Any invocation that leaves a
  pipe to stdin open blocks the agent until EOF.** `spawnSync` without
  `input` happens to close stdin immediately (which is why the baseline
  worked at all); an async port that keeps stdin open would deadlock. The
  protocol must close or ignore stdin explicitly.
- `--json` prints a JSONL event stream on stdout. Observed shapes:
  - `{"type":"thread.started","thread_id":"..."}`
  - `{"type":"turn.started"}`
  - `{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'echo hello-jumao'","status":"in_progress",...}}`
  - `{"type":"item.completed","item":{"id":"item_1","type":"command_execution","exit_code":0,"status":"completed",...}}`
  - `{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"..."}}` (multiple per turn; the last one is what `-o` writes)
  - `{"type":"turn.completed","usage":{...}}`
  This stream provides exactly the startup milestones the result model needs
  (process started → model response → first tool started → first tool
  completed → effective work).
- `-o <file>` writes the **last agent message** verbatim.
- The local user config injects a persona; even a "reply OK" prompt returned
  `爹，OK`. **The final message can never be assumed to be pure JSON**; any
  receipt parser must extract JSON leniently from surrounding prose.
- Benign stderr noise exists (a models-cache warning line) and must not be
  classified as an environment failure by itself.

## 5. Requirements derived for the fix

1. Replace the blind `spawnSync` with an asynchronous session runner that
   streams stdout/stderr to per-run files (no `maxBuffer` kill path), closes
   stdin at spawn, and records a timestamped lifecycle timeline.
2. Run the agent in its **own process group**; controlled cleanup signals the
   group (TERM → grace → KILL), verifies survivors, and can never signal
   anything outside the session's group.
3. Parse the `--json` event stream for startup milestones and activity-based
   stall detection instead of one flat wall-clock timeout.
4. Introduce a machine-readable Completion Receipt with harness-side
   cross-validation against measured evidence (file diffs, re-run check exit
   codes, side-effect scanner); the receipt can never override evidence.
5. Report `startupResult` / `deliveryResult` / `lifecycleResult` separately;
   never collapse them into one FAIL.
6. Preserve the full failure scene (events, stderr, timeline, receipt,
   process-tree snapshot, diffs, check outputs) under `benchmark/results/`,
   outside the disposable temp root.

The design that implements these requirements is
`docs/V0_4_COMPLETION_LIFECYCLE_SEMANTICS.md`.
