# `existing-node-cli-refactor` Codex execution comparison

## Scope and controls

- Case input: the `existing-node-cli-refactor` object from `benchmark/cases.js` was materialized separately for both runs. The input files were identical before planning and execution (ordered per-file SHA-256 digest: `0d7451fe9bd861bf47896af740f78abc77066c7e60c3b17a017cb2b85fc325a3` for each).
- Planning runtime: v0.3.1 used a detached temporary worktree at Git tag `v0.3.1` (`80cbd3611a6aaff124c4ea84f1682204d9fd168a`); v0.4 used the current working-tree runtime directly. The runtime file hashes were respectively `9a6a205c8377e2daba9d4166caa5588380dd8bd9` and `09f48ed077c3cfe42ea6eb3d28bde9404710a4e0`.
- Execution: each plan was implemented in its own temporary project directory. Neither project was committed, and no project files in the Jumao working tree were modified by execution.
- Execution prompt, used unchanged for both runs: `Implement only the requested change using the supplied Jumao plan. Preserve all stated constraints. Work in this temporary project only. Do not commit. Run the project tests and report commands, modified files, unmet plan items, invalid changes, constraints violations, human interventions, and rework loops.`

The requested change was to add `--json` to the existing `report` command while preserving its text output, without converting it to a web service, cloud service, or account system.

## Result

| Measure | v0.3.1 | v0.4 |
| --- | --- | --- |
| Goal completion | Complete: `node bin/report.js --json` prints `{"items":0}` and text mode remains `items: 0`. | Complete: same observable result. |
| Test / build result | `npm test`: 2 passed, 0 failed. No build script exists in the case fixture. | `npm test`: 2 passed, 0 failed. No build script exists in the case fixture. |
| Invalid modifications | 0 | 0 |
| Missing necessary changes | 0 for the stated fixture goal. The desired JSON field name was not separately specified; `items` is the only field supported by the pre-existing text output. | 0 for the stated fixture goal; same field-name limitation. |
| Human interventions | 0 | 0 |
| Rework loops | 0; implementation and tests passed on the first verification run. | 0; implementation and tests passed on the first verification run. |
| Modified file count | 2 | 2 |
| Modified files | `bin/report.js`, `test/report.test.js` | `bin/report.js`, `test/report.test.js` |
| Constraint compliance | Compliant: preserves text output; adds no web, cloud, or account capability. | Compliant: preserves text output; adds no web, cloud, or account capability. |

## Exact commands and observed output

Planning commands (the case was materialized in a different temporary directory per version):

```sh
node /var/folders/4b/kfn2_7111fj6x8nm9v8_rrl40000gp/T/jumao-execution-existing-node-cli-dKx1HK/v0.3.1-source/bin/jumao.js plan /var/folders/4b/kfn2_7111fj6x8nm9v8_rrl40000gp/T/jumao-execution-existing-node-cli-dKx1HK/v0.3.1/project --force
node /Users/smianmian/jumao/bin/jumao.js plan /var/folders/4b/kfn2_7111fj6x8nm9v8_rrl40000gp/T/jumao-execution-existing-node-cli-dKx1HK/v0.4/project --force
```

The same verification commands were run in each temporary project:

```sh
node bin/report.js
node bin/report.js --json
npm test
```

Both runs produced:

```text
items: 0
{"items":0}
tests 2; pass 2; fail 0
```

The execution diff in each project was limited to the CLI branch for `--json` and two regression assertions: one for unchanged text output and one for JSON output. Planning artifacts (`.jumao/` and `tasks/`) were excluded from the execution-change count.

## Interpretation

This case does not show an execution-quality advantage for v0.4: both plans contained the same direct product goal and produced the same minimal, passing implementation with no rework or constraint violation. It does show that v0.4's reduced role task set did not prevent successful execution of this simple Node CLI change. One case is not sufficient to establish a general execution-quality claim.
