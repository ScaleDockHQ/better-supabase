---
"better-supabase": minor
---

`better-supabase/server` exports `toCsv`, `csvColumns` and `csvResponse`, which answers with a CSV attachment. The `sessions` SQL module adds `better_supabase.last_sign_ins(uuid[])`, callable by the service role only, and `better-supabase/server` exports `lastSignIns` to read many users' last sign-in in one query. Run `better-supabase sql sync` to write the function.
