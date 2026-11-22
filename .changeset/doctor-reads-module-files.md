---
"better-supabase": patch
---

BS725 also reads the module files better-supabase writes under `supabase/schemas`, names the module in the finding, and no longer counts a `cron.schedule` lookup inside a string as a call.
