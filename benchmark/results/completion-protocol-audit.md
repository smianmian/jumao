# Codex Completion Lifecycle Audit

## Evidence boundary

Audited commit: `85d9a9f5960fa6ffbabcaafe3f1247b2fd31fbf9`.

The archived execution records retain fixture/runtime hashes, model arguments, file changes, validation commands and their complete captured output. The prior harness deleted temporary worktrees and did **not** retain Codex stdout/stderr, tool-call timestamps, process trees, PID records, or a completion receipt. Consequently, any category requiring those missing records is `unknown`, rather than inferred.

Current CLI inspection confirms `codex-cli 0.141.0`. `codex --help` states that bare `codex` is interactive and `codex exec` is the supported non-interactive command; the prior harness already used `codex exec --ephemeral --skip-git-repo-check -s danger-full-access -m gpt-5.6-terra -c model_reasoning_effort=\"high\" -c service_tier=\"default\" -C <worktree> -o <last-message> <prompt>`. No CLI upgrade was performed.

## Per-run classification

| Case / run | Delivery evidence | Validation evidence | Codex process record | Last Codex stdout / tool call | Root cause | Lifecycle |
| --- | --- | --- | --- | --- | --- | --- |
| SaaS 1 | 5/5 goals; files and tests saved | `npm test=0` | `status=null` | not retained | `unknown` | completed but non-clean |
| SaaS 2 | 5/5 goals; files and tests saved | `npm test=0` | `status=null` | not retained | `unknown` | completed but non-clean |
| SaaS 3 | 5/5 goals | `npm test=0` | `status=0` | not retained | n/a | clean exit |
| Health 1 | 4/4 goals and files saved | build 0; test 65 | `status=null` | not retained | `unknown` | completed work; validation failed; non-clean |
| Health 2 | 4/4 goals and files saved | build 0; test 0 | `status=null` | not retained | `unknown` | completed but non-clean |
| Health 3 | 4/4 goals and files saved | build 0; test 0 | `status=0` | not retained | n/a | clean exit |
| CLI 1 | 2/2 goals | test/text/JSON commands all 0 | `status=0` | not retained | n/a | clean exit |
| CLI 2 | 2/2 goals | test/text/JSON commands all 0 | `status=0` | not retained | n/a | clean exit |
| CLI 3 | 2/2 goals | test/text/JSON commands all 0 | `status=0` | not retained | n/a | clean exit |

For every non-clean run, the archived record shows no receipt and no process-tree/termination-action fields. No user input wait, live child process, last useful action, elapsed time after it, or unsaved result can be established from these artifacts. The files and test output were saved; the prior report's temporary `finalOutput` paths no longer exist after cleanup.

## Findings

The audit cannot prove an interactive-session issue: the command was already the official non-interactive `codex exec` mode. It can prove an observability defect: no machine-readable completion signal was required and no lifecycle/process evidence was persisted. The repair must add a session-only receipt plus explicit `running → completion_received → process_exited → cleanup_complete` evidence before future runs can classify non-clean exits without guessing.
