# Getting started

[中文](getting-started.zh-CN.md) · Preview **[v0.4.0-rc.2](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2)**

For people who **may not write code**, but want AI to help build an app.

---

## The product path (learn this first)

```text
  Idea
    → Jumao understands you
    → Plan / task package
    → AI coding agent develops (same folder)
    → Verify, then you decide launch
```

You do **not** need to memorize commands on day one. On a Mac you can do almost
all of this with the **Jumao Cat** app.

---

## Path A — Jumao Cat (macOS, recommended)

1. Download
   [**Jumao Cat v0.4.0-rc.2 Preview**](https://github.com/smianmian/jumao/releases/tag/v0.4.0-rc.2).
2. Unzip → move `Jumao Cat.app` to **Applications** → open from Applications.
3. Choose a folder (empty = new idea; existing project = a change).
4. Answer a few plain-language questions.
5. Confirm Jumao understood you; let it prepare the plan.
6. Review the plan (first steps, protections, anything blocked).
7. Click **Hand to AI Coding Agent** (instructions can mention Codex, Claude
   Code, Cursor, etc. as examples).
8. In that tool, open the **same** folder and paste the instruction.
9. When the agent claims finished, you decide next steps; optional verify is
   available via CLI on projects you trust.

No Node.js install is required for the app path.

---

## Path B — CLI (developers / non-Mac)

### Install

```bash
npm install -g jumao@rc
```

Use **`jumao@rc`** for Preview **0.4.0-rc.2**.

### Main developer flow

```bash
jumao new "My first app" --dir ./my-first-app
cd ./my-first-app

jumao interview .
jumao check --strict .
jumao audit . --write
jumao pack --target codex .
# or: --target claude | --target cursor
```

| Step | Meaning |
|------|---------|
| `new` | Create folder + starter product files. |
| `interview` | Save plain-language answers. |
| `check --strict` | Required product files exist and are not empty. |
| `audit --write` | Gap / risk notes before coding. |
| `pack` | Task packet for your **AI coding agent** (Codex is one `--target`). |

Then open the same folder in the agent and paste the packet.

After the agent finishes (trusted projects only):

```bash
jumao verify .
jumao verify . --no-run-checks
```

### Advanced diagnostics (optional)

```bash
jumao doctor .
jumao doctor . --write
```

Use **`doctor`** when you want an interactive deeper checkup. It is **not** part
of the main pack path; the standard pre-pack report is **`audit`**.

---

## Checklist: first success

- [ ] App installed **or** `jumao@rc` installed  
- [ ] Folder chosen / created  
- [ ] Jumao understood your idea (app questions or `interview`)  
- [ ] Plan or task packet exists  
- [ ] Same folder opened in an AI coding agent and packet pasted  

You do not need a full store listing on day one.

---

## Next

- [How Jumao works](concepts/how-jumao-works.md)  
- [README](../README.md)  
