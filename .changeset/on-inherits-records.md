---
"better-supabase": patch
---

A block's `on.<type>` entry for a type `config.records` registers inherits `table` and `idType` everywhere: `add`, `upgrade`, `gen`, `sql --adopt` and doctor now read `config.records` too, so they no longer fail with "needs a table" where rendering already merged the entry.
