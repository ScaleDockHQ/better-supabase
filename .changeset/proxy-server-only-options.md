---
"better-supabase": minor
---

Breaking: `createProxy` from `better-supabase/next/proxy` no longer accepts the options only `createNext` reads (`support`, `postgres`, `kept`, `authorizer`, `authorization`, `versions`, `credentials`, `audit` and `approval`). The proxy never used them, and passing them pulled a SQL support store, a Postgres pool or the authorizer into the proxy bundle and its cold start. Remove them from `proxy.ts`; a JavaScript caller that still passes one gets a warning. `CreateProxyOptions` is the new options type. `better-supabase/next/proxy` also exports `vercelRuntimeCache`, so a proxy that shares its JWKS through the Vercel Runtime Cache no longer imports `better-supabase/server`.
