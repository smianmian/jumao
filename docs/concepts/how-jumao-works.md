# How Jumao works

[中文](how-jumao-works.zh-CN.md) · [Getting started](../getting-started.md)

This page is **not** the homepage. It explains the control-layer model after you
know the product path:

**Idea → Jumao understands → plan / pack → AI coding agent develops → verify → you launch.**

---

## Two ways to say the same product

**Everyday:** Jumao helps people who do not write code use AI to take an app
from idea toward something real — by fixing the plan before the AI codes.

**Developer:** Jumao is the **decision and delivery control layer** for AI
coding agents. The agent still edits the repo; Jumao shapes goals, scope,
evidence, audit, and the pack the agent should follow.

```text
  You (goals, go/no-go on real world)
       │
       ▼
  Jumao (decide + pack + optional verify)
       │
       ▼
  AI coding agent (implement — e.g. Codex, Claude Code, Cursor)
       │
       ▼
  Your machine / stores (you still publish)
```

Agents are not limited to one vendor. Pack targets (`codex`, `claude`, `cursor`)
are formats; the product action is **hand to AI coding agent**.

---

## Core ideas

### Goal

What this version must achieve for a real person — and what “done” looks like.

### Evidence

Proof that something is true or finished: product files, tests, logs,
screenshots, or a completion receipt. Claims without evidence are not completion.

### Scope

What is **in** this version and what is **out**. Explicit “do not build yet”
limits stop the agent from expanding early.

### Audit

Structured gap / risk review before coding (`jumao audit`). Writes plain-language
notes (often under `governance/`) so the pack is safer.

**`jumao doctor`** is an **advanced, interactive diagnosis** path — useful when
you want a guided checkup, not a required step in the main flow.

### Pack

A **task packet** (`jumao pack --target …`) the coding agent consumes: boundaries,
gates, and next safe work. Main bridge from Jumao into the agent.

### Execution boundary

What the agent may do **now** (usually prepare and validate in a local folder)
versus what stays blocked until a human confirms (production, real payments,
store submission, irreversible live data).

Planning and packing stay **local** and do not require a Jumao cloud AI API.

---

## CLI map (developer path)

| Step | Command | Control-layer job |
|------|---------|-------------------|
| Create home | `jumao new` | Workspace + starter files |
| Capture intent | `jumao interview` | Goals and scope as answers |
| Gate files | `jumao check --strict` | Required artifacts present |
| Audit | `jumao audit --write` | Gaps before coding |
| Handoff | `jumao pack --target …` | Packet for AI coding agent |
| (Optional) Plan UI/runtime | `jumao plan` / Jumao Cat | Local planning + readable plan |
| (Optional) Deep checkup | `jumao doctor` | Advanced diagnostics |
| (After agent) | `jumao verify` | Check completion claims |

---

## What stays outside Jumao

- Writing product UI/business code (the coding agent)  
- Your judgment on taste and priorities  
- Store / deploy accounts and legal entity choices  

---

## Safety

- Source read-only by default during inspect / plan  
- Full `jumao verify` may run project tests — trusted trees only  
- Human confirmation for real users, money, review, production  

---

## Related

- [Getting started](../getting-started.md)  
- [README](../../README.md)  
