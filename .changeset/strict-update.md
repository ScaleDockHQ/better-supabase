---
"better-supabase": minor
---

`deals.update` takes `{ changes, strict }` instead of the changes array. Both `deals.update` and `tasks.update` accept `strict: true`, which returns the first refused change as a `raised` error that keeps its hint as the code, instead of listing it in `rejected`. Wrap an existing call as `update({ changes })`.
