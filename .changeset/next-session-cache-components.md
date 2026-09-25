---
'better-supabase': minor
---

Next.js Cache Components support. `next.session()` returns the verified caller
as serializable data (no token, no clients), ready to wrap in a
`'use cache: private'` function. `SessionProvider` and `useSession()` in
`better-supabase/react` share that session promise with Client Components, and
the `react-server` build renders `SessionProvider` as a client reference so a
Server Component layout can pass the promise inside `<Suspense>`. `toSession()`
and the `AuthSession` type are exported from `better-supabase/next` and
`better-supabase/ssr`.
