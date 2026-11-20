---
"better-supabase": patch
---

Correct the `persistSessions` doc comment: eve does not retry or rerun hooks, so a missed hook is not replayed.
