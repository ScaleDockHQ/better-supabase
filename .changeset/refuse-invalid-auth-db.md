---
"better-supabase": patch
---

Queries through `ctx.db` and `server.dbFor` with credentials that did not verify now return the unauthorized `DbError` instead of running as anon, so a handler without a route guard cannot read data with a bad token.
