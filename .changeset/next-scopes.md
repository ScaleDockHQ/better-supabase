---
'better-supabase': minor
---

Cheaper private-cache scopes in Next.js. Verified access tokens are remembered until they expire, so
twelve islands check the signature once, and `db`, `supabase` and `sql` on a server context are built
on first use. New: `next.cached()` (session-aware `cacheLife` plus a `bs:session:<id>` tag),
`next.invalidateSession(userId)`, `next.serverFor(session, { token })`, `server.contextFor(auth)` and
`sessionStale(session)`.
