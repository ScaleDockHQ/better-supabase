---
"better-supabase": patch
---

Fixes in the Next.js adapter, the server, the Expo storage and PowerSync.

`sessionStale` returns 0 for a signed-out view that a refresh or a sign-in would change (an `anon` session that is `expired` or `refresh_failed`, and an `invalid` one), so it no longer lands in the per-session App Shell. A token with fewer than `min` seconds left now gives 0 instead of `min`, so a view is never reused past the token's expiry.

A `redirect()` or `notFound()` after a write in `bs.action()` or `bs.route()` now still sets the replica pin cookie and hands pending event sends to `after()`. `handle()` flushes event sends when `rethrow` throws as well.

Mutations outside a Server Action expire their cache tags with `revalidateTag(tag, { expire: 0 })` instead of `'max'`, so a read after a write in a route handler gets fresh data. `nextCache({ revalidate })` keeps the old behavior with `'max'`, and the new `NextCacheOptions` type describes it.

`contextForSession()` returns the `invalid` context of an expired token or an unreachable JWKS with its own error, instead of reporting that the token belongs to another session.

`server.context()` looks up the support session while the tenant resolver runs, instead of after it.

`secureStorage()` runs the operations on one key one at a time and writes a new value into a second set of chunk keys before it switches `<key>.chunks` to them, so a read never joins chunks of two sessions and a failed write keeps the previous session. Values stored by earlier versions still read.

`watch()` never starts when its signal is already aborted and removes its abort listener when stopped. The PowerSync executor runs a read's rows and count in one `readTransaction` when the database has one.
