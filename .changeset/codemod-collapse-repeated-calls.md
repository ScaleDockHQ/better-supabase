---
"better-supabase": patch
---

`codemod 0.15` no longer leaves a script running the same command twice. It rewrites both `sql sync` and `sql upgrade` to `upgrade`, so a `package.json` script or a workflow `run:` step that called both now calls `upgrade` once. Only identical commands next to each other and joined by `&&` collapse.
