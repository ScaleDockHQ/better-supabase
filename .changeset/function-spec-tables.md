---
"better-supabase": minor
---

`s.$fn.<name>(args, { tables })` declares the tables a SQL function reads, so `bsb.tags` and `bsb.cached({ readSet })` tag a cached function payload with them and a mutation of one of those tables revalidates it. `bsb.tags` also takes a function call alone or in a list. The `FunctionSpec` and `FunctionSpecOptions` types are exported.
