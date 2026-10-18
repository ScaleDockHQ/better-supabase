---
"better-supabase": patch
---

`better-supabase codemod 0.9` puts the moved `blocks` key in sorted position when the config's top-level keys are already sorted, so a config checked by a `sort-keys` lint rule stays valid. A config with unsorted keys still gets `blocks` right after `sql`.
