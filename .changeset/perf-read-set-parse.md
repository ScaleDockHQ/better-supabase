---
"better-supabase": minor
---

Check a read set result with `readSet.parse(value)`, and find groups of parallel reads with `better-supabase codemod read-many`, which lists each `Promise.all` that `db.$many` can load in one round trip. Doctor BS609 counts `$rpc` and block calls in the same `Promise.all`.
