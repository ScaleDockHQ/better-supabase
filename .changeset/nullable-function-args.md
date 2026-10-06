---
"better-supabase": patch
---

Generated function arguments accept `null`: `Functions[name]["Args"]` types each argument as `T | null`, since Postgres passes `null` to any argument of a function. Before, passing `null` to `db.$rpc` needed a cast. Arguments with a default stay optional. Regenerate with `better-supabase gen`.
