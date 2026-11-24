---
"better-supabase": patch
---

`upgrade`, `doctor`, `gen` and `add --adopt` start faster and use less memory: the adoption check reads the default SQL of only the blocks it asks about, and only when its cached result is missing, and each SQL text is scanned once.
