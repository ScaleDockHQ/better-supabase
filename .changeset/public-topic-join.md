---
"better-supabase": patch
---

`subscribe()` on a public topic (`private: false`) joins the channel again. It used to resolve `ready` without joining, because the check for remaining subscribers ran before the first one was added, so no messages arrived.
