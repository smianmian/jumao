# Getting started with Jumao

**Preview: [v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)** · [中文](getting-started.zh-CN.md)

This page is for a **first successful run**: install → describe → plan → hand to AI.

You do not need to be a programmer. You need an idea (or a change you want), a
folder on your computer, and an AI coding tool you can paste instructions into.

---

## 1. Install

### Path A — Jumao Cat (macOS app)

Best if you prefer buttons and a menu bar cat.

1. Open the [v0.4.0-rc.2 Preview release](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2).
2. Download **`JumaoCat-v0.4.0-rc.2-arm64.zip`**.
3. Unzip it.
4. Drag **`Jumao Cat.app`** into **Applications**.
5. Open it from **Applications**.

Needs: Mac with Apple silicon, macOS 14+. No separate Node install for the app.

### Path B — CLI

Best if you already use a terminal.

```bash
npm install -g jumao@rc
jumao --help
```

Use **`jumao@rc`** so you get the Preview line (0.4.0-rc.2).  
Do not treat older tags as the default entry for new work.

---

## 2. Prepare a folder

| Goal | Folder |
|------|--------|
| Brand-new idea | Create an empty folder (e.g. Desktop → `my-first-app`) |
| Change an existing project | Use that project’s root folder |

Jumao will read what it needs from that folder (read-only while planning) and
write planning notes under `.jumao/` plus a plan under `tasks/` when ready.

---

## 3. First run with the app

1. Click the cat in the menu bar (or open the main window).
2. Choose your folder.
3. Answer the short questions in everyday language:
   - **New project:** What is it? What should it do? Where do you use it first?  
     Optional: what must this version **not** do?
   - **Existing project:** What should this change become?
4. Confirm that Jumao’s summary matches what you meant.
5. Wait for local planning to finish (progress appears in the app).
6. Open the development plan and skim:
   - first steps  
   - things that must stay protected  
   - anything blocked until you decide  
7. Click **Hand to Codex** (or copy the instruction for Claude Code / Cursor).
8. In that AI tool:
   - open the **same** folder  
   - paste the instruction  
   - let it work only on that plan  

When the AI says it is finished, you can come back later and use verification
tools (see below) on projects you trust.

---

## 4. First run with the CLI

```bash
cd /path/to/your-folder

# Optional: answer questions in the terminal
jumao interview .

# Produce / refresh the local plan
jumao plan .

# After your coding agent finishes (trusted projects only)
jumao verify .
# or, without running the project's tests:
jumao verify . --no-run-checks
```

Open `tasks/jumao-agent-plan.md` (path may be shown in the plan output) and paste
the handoff into your AI coding agent with that folder as the workspace.

---

## 5. What “done” looks like for a first session

You are done with **Jumao’s first job** when:

- [ ] You have a folder Jumao knows about  
- [ ] You confirmed the plain-language understanding  
- [ ] A plan exists you can read in normal language  
- [ ] You pasted the handoff into an AI coding agent on the **same** folder  

You are **not** required to finish the whole app in one sitting. Jumao is for
one clear slice at a time.

---

## 6. Common questions

**Does Jumao write my app code?**  
No. The AI coding agent does. Jumao prepares the plan and boundaries.

**Does it need an OpenAI / cloud API key?**  
Not for planning. Your coding agent may need its own account separately.

**Will it upload my project?**  
Planning is local. Do not run full `jumao verify` on untrusted projects if you
do not want their test scripts executed.

**I only have Windows / Linux**  
Use the CLI (`jumao@rc`). The menu bar app is macOS-only in this Preview.

**I found an old v0.3.1 download**  
That is historical. Prefer **v0.4.0-rc.2 Preview** for the current product.

---

## Next reading

- [How Jumao works](concepts/how-jumao-works.md) — control layer vs coding agent  
- [Guide](guide.md) — optional product templates  
- [Main README](../README.md)  
