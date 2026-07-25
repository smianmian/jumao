# Semantic-repair Codex execution: `existing-node-cli-refactor`

## Scope and controls

This is an execution comparison, not a release result. It uses two isolated temporary Git projects and does not modify, merge, tag, publish, or execute in the Jumao source workspace. The harness made a **pre-execution fixture-baseline commit** in each temporary project solely to measure the Codex diff; Codex made no commits and no execution result was committed.

| Control | v0.3.1 baseline | v0.4 semantic repair |
| --- | --- | --- |
| Planning source commit | `3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567` | `277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64` |
| Planning-runtime SHA-256 | `4823c5657ece9c46c83a90f9963066f68b559d29c9eb9aedb23f83b55fd0686f` | `13313da367a2fce6ef28c11da19691be5c9f8a956959f02517c0f1b595ee5159` |
| `benchmark/cases.js` SHA-256 | `f883ac55e1f93ca5b3014c7a7fa514d9bf1e399418ef6da3341491a0d7499f57` | `f883ac55e1f93ca5b3014c7a7fa514d9bf1e399418ef6da3341491a0d7499f57` |
| Materialized-input manifest SHA-256 | `02e624ed93e59af38027f0d4da9b0a2c02233c25b0d5ae9c754a124fcd6c36b2` | `02e624ed93e59af38027f0d4da9b0a2c02233c25b0d5ae9c754a124fcd6c36b2` |
| Planner result | 9 completed-agent tasks; 5 native `priorityTasks` | 2 native `priorityTasks` |
| Codex CLI | `codex-cli 0.141.0` | `codex-cli 0.141.0` |
| Pre-execution fixture commit | `78c0bf4296d9d00b2f03949fda440845c63171f2` | `b823a109bfcc036d8fb80ef8df5eba019f4730ff` |
| Codex model/config | `gpt-5.6-terra`, `model_reasoning_effort="high"`, `service_tier="default"`, `--ephemeral -s danger-full-access` | Identical |

The two runtime trees were created with `git archive`, rather than a worktree, at `/tmp/jumao-semantic-cli-git.y61TRB`. The fixture was materialized from the `existing-node-cli-refactor` object in the identical `benchmark/cases.js` file before either planner ran. The input manifest covers `package.json`, `bin/report.js`, `src/report.js`, `test/report.test.js`, `product/compatibility.md`, and `.jumao/intake-answers.json` in sorted order. The distinct runtime hashes demonstrate that this did not execute the same runtime twice.

Each planner wrote its generated `tasks/jumao-agent-plan.md`; that exact file was also copied unchanged to `JUMAO_PLAN.md` in its own temporary project as the supplied plan. Each project was then initialized and committed before Codex began; the pre- and post-execution `HEAD` values above are identical. The baseline plan listed nine completed-agent tasks (and five native priority tasks); semantic repair listed two completed-agent tasks and two native priority tasks. These are reported separately because they are different planner representations, not interchangeable measures.

## Exact execution prompt and commands

The following prompt was passed byte-for-byte to both Codex runs:

```text
Implement only the requested change using the supplied Jumao plan. Preserve all stated constraints. Work in this temporary project only. Do not commit. Run the project tests and report commands, modified files, unmet plan items, invalid changes, constraints violations, human interventions, and rework loops.
```

The same CLI shape and explicit model settings were used for each run (only `-C` and `-o` paths differ):

```sh
codex exec --ephemeral -s danger-full-access \
  -m gpt-5.6-terra -c 'model_reasoning_effort="high"' \
  -c 'service_tier="default"' -C <temporary-project> \
  -o <temporary-codex-final.md> '<prompt above>'
```

After Codex exited, the harness independently ran, in each corresponding temporary project:

```sh
npm test
node bin/report.js
node bin/report.js --json
git diff --check
git diff --name-only
git rev-parse HEAD
```

`package.json` has no `build` script in either identical fixture, so there is no build command to run. The harness recorded `NO_BUILD_SCRIPT` rather than treating a nonexistent build as passing.

## Independently verified outcome

The core requested goal is: add `report --json`, preserve the original `report` text output, and do not turn the CLI into a web service, cloud service, or account system.

| Measure | v0.3.1 baseline | v0.4 semantic repair |
| --- | --- | --- |
| Core goal completion | Complete: `node bin/report.js` prints `items: 0`; `node bin/report.js --json` prints parseable `{"items":0}`. | Complete: identical observed outputs. |
| Independent test result | `npm test`: 2 passed, 0 failed. | `npm test`: 2 passed, 0 failed. |
| Build result | No build script exists. | No build script exists. |
| Plan tasks actually executed | 2 functional items: implement `--json`; add regression coverage for default and JSON output. Plan/file inspection also occurred, but is not counted as a code task. | 2 functional items, using the same counting rule. |
| Modified product files | 2: `bin/report.js`, `test/report.test.js`. | 3: `bin/report.js`, `src/report.js`, `test/report.test.js`. |
| Diff whitespace check / commit check | `git diff --check` passed; `HEAD` remained at the pre-execution fixture baseline. | Same. |
| Invalid modifications | None found by the independent changed-file inventory. | None found by the independent changed-file inventory. |
| Constraint violations | None: text mode retained; product document unchanged; no web, cloud, account, secret, or release change. | None by the same checks. |
| Required-change omissions | None for the fixture's stated goal. The JSON field name was not specified; both implementations use the only existing signal, `items: 0`, to produce `{ "items": 0 }`. | None for the fixture's stated goal. |
| Human interventions | 0 during execution. Codex treated the supplied implementation prompt as the plan's requested owner confirmation; no follow-up input was needed. | 0. |
| Rework loops | 0: passing implementation on its first verification cycle. | 0. |

The baseline implementation serialized the known fixture value directly in the CLI branch; repair introduced a shared report object and `renderReportJson()` helper in `src/report.js`. Both are within scope and both preserve the existing `renderReport()` contract. The different file counts therefore show two acceptable minimal implementations, not a quality win for either version.

## Plan omissions and limits of this comparison

Neither run added an error-output contract, argument validation, or a richer report schema, because the fixture and supplied plan do not specify those behaviors. Calling those missing would reward invented requirements. Conversely, the baseline's additional generic agent tasks (data/privacy, user-flow, UI-state, CI record keeping) were not separate product requirements in this Node CLI fixture; they are not counted as unmet implementation work.

This case demonstrates that semantic repair's two-task plan remained sufficient for a small, direct CLI change. It does **not** demonstrate execution superiority: both runs completed the goal, passed the same independent checks, required no intervention or rework, and complied with all stated constraints. A broader release conclusion must rely on the other independently executed cases and the semantic-repair audit, not on this tie.
