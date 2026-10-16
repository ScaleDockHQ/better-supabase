---
"better-supabase": minor
---

`httpSink` aborts a request after `timeoutMs` (10 seconds by default) instead of waiting on an endpoint that never answers. `doctor` gives up on the splinter download and the Management API advisors after 30 seconds.
