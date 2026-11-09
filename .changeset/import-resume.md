---
"better-supabase": minor
---

`runImport` reads `accessToken` before every batch and retries once when the request reports an auth failure. A dropped batch returns `resumeFrom`. Passing that as `resume` continues the same run from that chunk, so the earlier chunks are not sent again.
