# AI Agent Prompts

Use these prompts with Codex, Claude Code, Cursor, or another AI coding tool. Ask the AI to read the Jumao task packet before it edits code.

## First handoff

```text
Please read AGENTS.md, product/, and proof/ in this project first.
Do not write code yet.

Tell me in plain language:
1. Who this product is for;
2. What the first version includes;
3. What the first version explicitly excludes;
4. What information is missing;
5. The next smallest safe action.

If any action affects real users, production data, payments, launch, review, or external accounts, stop and ask me first.
```

## Start one small implementation task

```text
Implement only this small task:
<write the task here>

Before editing, explain:
1. Which first-version goal this serves;
2. Which files you expect to change;
3. Which areas you will not touch;
4. Which command or evidence will verify the result.

Start coding only after I confirm.
```

## Check whether the AI is drifting

```text
Check your work against the Jumao task packet:
1. Did you expand first-version scope?
2. Did you add anything the task packet explicitly excludes?
3. Did you touch real users, production data, payments, launch, review, or external accounts?
4. Did you leave tests, screenshots, logs, or human acceptance proof?
5. What still cannot be called done?
```

## Ask for completion proof

```text
Please write this round into proof/release-proof.md.

Include:
- What changed;
- What did not change;
- Verification commands and results;
- What still cannot be called done;
- Suggested next step.

Do not mark anything done without proof.
```

## Recommended Codex opener

```text
You are the Jumao product launch assistant.
Read AGENTS.md and jumao-task-pack.md first.
Summarize the goal, scope, risks, and next plan before editing code.
```

## Recommended Claude Code opener

```text
Please read CLAUDE.md, AGENTS.md, and the product/ files first.
Tell me the product goal, first-version scope, gaps, and next smallest safe action.
Do not code until I confirm.
```

## Recommended Cursor opener

```text
Treat AGENTS.md as project rules.
Before each edit, answer: which first-version goal does this change serve?
If the change expands first-version scope, stop and ask me first.
```
