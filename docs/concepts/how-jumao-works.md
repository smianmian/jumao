# How Jumao works

[中文](how-jumao-works.zh-CN.md) · back to [Getting started](../getting-started.md)

This page is for people who want the **product model**, not a code tour.
Internal pipeline names are explained only where they help trust the tool.

---

## Two layers of the same story

### For everyone

You can ship an app idea with AI even if you do not write code daily.

Jumao is the calm step before coding:

1. You say what you want in plain language.  
2. Jumao checks what it can see in your project folder.  
3. You get a plan you can read.  
4. An AI coding agent implements that plan in the same folder.

### For developers

Jumao is a **decision and delivery control layer** in front of an AI coding agent.

| Layer | Role |
|-------|------|
| **You** | Goals, taste, go/no-go on real users, money, publish |
| **Jumao** | Scope, boundaries, evidence, handoff, optional verify |
| **AI coding agent** | Edit files, run tools, implement tasks |
| **Your machine / stores** | Where code lives; App Store / deploy still need you |

Jumao does **not** replace Codex, Claude Code, or Cursor. It makes their job
smaller and checkable.

---

## What Jumao does on your machine

```text
  Answers (plain language)
  + optional project scan (read-only)
           │
           ▼
  Local planning (no cloud AI API for this step)
           │
           ▼
  Plan + notes under .jumao/ and tasks/
           │
           ▼
  You hand the plan to an AI coding agent
           │
           ▼
  Optional: verify the agent’s completion story
```

Important properties:

- **Local by default** — planning does not require Jumao cloud or model keys.  
- **Read-only source by default** while inspecting and planning.  
- **Explicit handoff** — usually `tasks/jumao-agent-plan.md` plus a short
  pasteable instruction.  
- **No silent publish** — release, pay, production data stay human-gated.

---

## What “planning” means here

When Jumao “plans,” it is not one chatbot guessing your product.

It runs a **fixed local checklist of professional concerns** (product, privacy,
release risk, and so on), grouped so you can see what applied, what was skipped,
and what is blocked waiting for a human decision.

You may see counts like “8 groups / 44 roles.” Think of them as **named review
lenses**, not 44 separate AIs coding in parallel.

Statuses you might see on a role:

| Status | Plain meaning |
|--------|----------------|
| completed | This concern looked relevant and produced useful notes |
| skipped | No trigger / no evidence this project needs it now |
| blocked | Something only you can decide is missing |
| failed | That check or write step could not finish |

---

## After the AI codes: completion and verify

Good handoffs ask the coding agent to leave a **completion receipt** (what
finished, what blocked, what was validated, whether it touched the real world).

`jumao verify` can re-read that receipt and compare it with:

- changes it can see (e.g. via git), and  
- optionally re-running the project’s own tests.

That is why full verify should only run on **projects you trust** — tests are
code. Use `--no-run-checks` when you only want static checks.

---

## What Jumao is not

- Not a replacement for learning product judgment  
- Not a guarantee the AI will obey (you still review)  
- Not an App Store publisher or payment processor  
- Not a hosted multiplayer “AI company” product in this Preview  

---

## Where to go next

- First run: [Getting started](../getting-started.md)  
- Install and overview: [README](../../README.md)  
- Optional templates: [Guide](../guide.md)  
