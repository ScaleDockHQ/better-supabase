---
"better-supabase": patch
---

Breaking: `allow: ['anon']` no longer admits users from `signInAnonymously()`. Only `'anonymous'` admits anonymous sign-ins, and `'anon'` means a caller without a session. `['anonymous']` alone now admits anonymous sign-ins and refuses other users; before, it admitted nobody. A route that serves guests next to signed-in users lists `['user', 'anonymous']`, and a public route that also serves guests `['user', 'anonymous', 'anon']`. With PermDock, pair the default `allow` with `rls: { anonymousSignIns: 'deny' }` in `permdock.config.ts`.
