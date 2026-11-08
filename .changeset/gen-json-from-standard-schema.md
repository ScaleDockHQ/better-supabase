---
"better-supabase": minor
---

`gen` types a jsonb column from the schema value that `standardSchema({ json })` names for it, so you no longer repeat the type in `gen.json`. An entry in `gen.json` still wins.
