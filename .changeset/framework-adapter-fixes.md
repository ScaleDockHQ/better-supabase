---
"better-supabase": patch
---

Fix drift in the framework adapters. The Next.js adapter sends cache tags to `cacheTag()` in chunks of 128, so a list longer than 128 no longer loses its tail. The TanStack Start page and the middleware file `better-supabase init` writes now include `createCsrfMiddleware`, because defining `src/start.ts` turns off Start's default CSRF protection for server functions.
