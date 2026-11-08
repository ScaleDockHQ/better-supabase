---
"better-supabase": minor
---

The UI recipes in the skill and the docs take plain ids and a `query` object instead of the `params` and `searchParams` promises, and read the clock behind `io()` from `next/cache` instead of `connection()`. The page resolves the route props with `params.then()`.
