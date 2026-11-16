---
"better-supabase": patch
---

`upgrade --preserve <file>` writes the new render to `<file>.new`, keeps the
hand-edited file, and writes the other blocks. The path never matched the
planned one, so it skipped the file, wrote no `.new` and stopped the rest.
