---
"better-supabase": minor
---

`observedFetch` from `better-supabase/server` wraps a `fetch` so each request reports its method, URL (without the query), status and duration to `onCall`. Pass it as `createServer({ fetch })` to count or trace the server's calls to Supabase. The observer can't change or fail a request.
