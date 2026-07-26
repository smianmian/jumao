# Completion Protocol Validation

- frozen baseline (not re-run): 3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567
- repair: HEAD
- repetitions: 1
- runs: 3

每次执行都使用独立临时 worktree、相同 Codex CLI/model/config/prompt 和 session-only sandbox execution context。
结果 JSON 位于 `runs/`；每次执行的事件流、stderr、时间线、回执与清理证据位于 `runs/<case>/repair-N-session/`。
