---
"better-supabase": minor
---

`blocks.sessions.options.bootstrap` accepts `{ readSet: "name" }` next to `"schema.function"`. The generated `bootstrap_<name>` wrapper then calls `public.rs_<name>`, so one page load carries the session check, the authorization version and a whole read set in one query.
