---
"better-supabase": minor
---

`better-supabase/next/proxy` exports `createProxy()`, the Next.js proxy without the Server Component side of `createNext`, and the proxy helpers `mutableResponse`, `overrideRequestHeaders`, `syncMiddlewareSetCookie` and `serverTimingValue`. `src/proxy.ts` imports it, so the proxy bundle carries no sign-in flows, record bindings or REST resources. `bsb.proxy()` is unchanged.
