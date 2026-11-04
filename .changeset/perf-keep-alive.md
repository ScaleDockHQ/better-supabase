---
"better-supabase": minor
---

`better-supabase/node` exports `keepAliveFetch({ connections, pipelining })`, a `fetch` for the
Supabase client that keeps sockets open through the optional peer `undici` and falls back to the
global `fetch` without it. `defineListQuery.run({ count: "planned" })` is documented, and
`tests/bench` holds a PostgREST floor script and an executor comparison.
