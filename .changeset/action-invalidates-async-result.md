---
"better-supabase": minor
---

`bsb.action` takes `invalidates`, a list of tables whose cache tags drop after a successful call (until now only `bsb.blockAction` did), and its `result` mapper may be async.
