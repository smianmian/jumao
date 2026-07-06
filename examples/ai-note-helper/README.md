# AI Note Helper

This is a filled Jumao example. It shows how a small app idea becomes a product
brief, first-version scope, screen states, data notes, and a task packet.

Run the example check and target pack:

```bash
node bin/jumao.js check examples/ai-note-helper --strict
node bin/jumao.js audit examples/ai-note-helper
node bin/jumao.js pack examples/ai-note-helper --target codex
```

Example goal: after a user enters a messy note, the product returns a title,
a short summary, and three next actions.

The `answers.json` file is used by the root README quickstart to fill a new
workspace through `jumao interview`.
