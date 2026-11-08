---
"better-supabase": minor
---

`AsyncResult.from` starts its run at once instead of one microtask later, and `AsyncResult.pipe` runs several chained calls as one `AsyncResult`: unwrap each step with `bind`, and the pipe stops at the first error. The tags block's `create` verb uses it.
