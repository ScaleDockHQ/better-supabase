---
"better-supabase": minor
---

In a support session, `ctx.storage` reads Storage as the target user, where `ctx.supabase` throws. `supportStorage({ admin, sql, readOnly })` is exported from `better-supabase/server` for the same reads outside the server context.
