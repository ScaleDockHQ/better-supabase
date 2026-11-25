---
"better-supabase": patch
---

The generated access matrix counts column-level grants, so a table that grants a role INSERT on some columns no longer reads as denied for it, and a "reaches no row" cell accepts a statement that a trigger or constraint refuses, as such a statement reaches no row either. Regenerate your access matrix tests to pick it up.
