---
"better-supabase": minor
---

`better-supabase codemod` no longer reads the SQL files the blocks wrote (module, data and test files). It writes a rename migration only for names your own SQL uses, because `upgrade` rewrites the block files.
