---
"better-supabase": patch
---

`createNext` takes `debug: { coldStart: true }`, which reports the first request of a process: how long `better-supabase/next` took to evaluate, when it was ready, and the first `createNext`, `warm()`, `getClaims` and query. The stats header gets a `cold=eval:…,ready:…,create:…,warm:…,claims:…,query:…` field while a step is new, and the first query logs one `bsb.cold` line, so an app can tell which part of a slow first request is the library's. It uses only `performance.now()`, so it runs on every runtime, and it collects request stats outside development like `debug.enabled`.
