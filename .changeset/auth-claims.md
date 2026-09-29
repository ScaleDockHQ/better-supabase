---
'better-supabase': minor
---

Typed, validated JWT claims. `sb.claims(schema)` takes any Standard Schema and returns a definition
whose servers validate the verified claims on every request, including memoized tokens. The output
is merged over the payload and types `ctx.auth.claims`, `next.session()`, `useSession` from
`createHooks<typeof browser>()` and the new generic `useSession<C>()`. `tenant<C>({ claim })`
accepts only dotted paths to string claims. A token whose claims fail resolves to
`{ kind: 'invalid', reason: 'claims' }` (401, `CLAIMS_INVALID`) and is never refreshed. The
`invalid` state now always has a `reason` (`'token'` or `'claims'`). `AuthResolver`s may leave it
out, and it then counts as `'token'`.
