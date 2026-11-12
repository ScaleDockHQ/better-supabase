---
"better-supabase": patch
---

Doctor BS219 attributes a containment filter in a function to the tables that function names. Before, it joined every function definition together, so a function that only named a table flagged that table's jsonb column whenever any other function used `?` or `@>` on a column of the same name.
