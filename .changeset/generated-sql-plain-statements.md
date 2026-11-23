---
"better-supabase": patch
---

The module files `better-supabase gen` writes name `for role postgres` in every `alter default privileges` statement, and the `autoEmbed` drain and the queue `httpTick` job are plain `select cron.schedule(...)` statements, so doctor BS725 no longer reports them under pg-delta. Run `better-supabase gen` and review the module file diff. See the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83).
