---
"better-supabase": minor
---

`ServerOptions.sessions` takes `counters`, an object the verified-token memo counts its hits and misses on, so several servers in one process (a Next.js route handler is bundled apart from the pages) report one total. The memo's own `stats()` reads it. Nothing changes without the option. `upgrade` rewrites no module and no data migration is needed.
