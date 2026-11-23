---
"better-supabase": patch
---

Request stats count a read that a `"use cache: private"` function makes through `bsb.cached()` with no session handle, including its time. This was already the case in 0.85; a test now holds it to the shape CentraKit uses for its order payload RPC.
