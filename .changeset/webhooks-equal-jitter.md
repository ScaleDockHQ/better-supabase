---
"better-supabase": patch
---

The outgoing webhooks block's default retry backoff uses equal jitter: each wait is at least half its step and at least a second. Full jitter could schedule a retry for the same instant as the failure, so a struggling receiver got hit again at once.
