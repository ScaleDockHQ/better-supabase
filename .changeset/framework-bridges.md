---
"better-supabase": minor
---

Bridges run an `@supabase/middleware` entry array in a framework's middleware slot and return the framework's response back through the entries. `toHono` (`better-supabase/hono`), `toEdge` (`/edge`), `toOrpc` (`/orpc`) and `toExpo` (`/expo`) join the existing adapters, and five new subpaths add `toTanStackStart` (`better-supabase/tanstack-start`), `toSvelteKit` (`/sveltekit`), `toReactRouter` (`/react-router`), `toH3` (`/h3`, for Nitro and Nuxt too) and `toElysia` (`/elysia`). The new bridges are typed structurally and add no dependency. They replace the `@supabase/server` framework adapters, which are deprecated upstream and removed on 2026-12-01.

`createHono().middleware()`, `createEdge().handler()`, `createEdge().resources()` and `createExpo().handler()` now run on `withBetterSupabase`, with the same options and responses.
