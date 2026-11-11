---
"better-supabase": patch
---

`db.$many` asks a read set's permission gates in one wave instead of one after another, and starts the set's function entries beside its table batch when the connection can't send the whole set as one call. The results are the same.
