---
"better-supabase": minor
---

`createSafeFetch` takes `sensitiveHeaders`, more header names (such as `x-api-key`) that a redirect to another origin drops on top of `authorization`, `cookie` and `proxy-authorization`, so requests that send credentials in other headers can follow cross-origin redirects without leaking them.
