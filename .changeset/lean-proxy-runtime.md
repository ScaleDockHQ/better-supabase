---
"better-supabase": patch
---

`createProxy` from `better-supabase/next/proxy` no longer bundles the server's clients and query builder. It builds from the session runtime that `createServer` also uses, so a page and the proxy still share one JWKS cache and one session memo. The shipped proxy shrinks from 64.8 KB to 47.7 KB gzipped.
