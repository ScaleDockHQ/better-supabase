---
"better-supabase": minor
---

Keep plugin and adapter state per definition. Plugins get an optional `context(context, { schema })` hook that runs once per `connect()` and `$with()`; `tenant()` uses it to set `db.$context.tenant` from its own claim paths, and jobs, storage and cache invalidation read that value, so two definitions with different claim paths in one process no longer share a resolved tenant. `testPlugin` checks that a `context` hook is pure. A second `defineSupabase` call with a different `temporal` namespace now logs a warning, and each definition's default clock uses its own namespace. In Next.js, each `createNext` call applies its own stats budget and logger, and running `createNext` again for a definition no longer invalidates every cache tag twice.
