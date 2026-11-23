---
"better-supabase": minor
---

`better-supabase codemod table-tags --explain` lists each audit exemption, `data-lifecycle` table and `expose` entry that would move into a comment tag, says whether the render or only doctor reads the tag, and writes nothing. Before it moves a `data-lifecycle` or `expose` entry, the codemod reads the config back through the tag and keeps the entry in the config when the value differs. See ADR 1188.
