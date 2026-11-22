---
"better-supabase": minor
---

`db diff --in-stack` and `db squash` name the pg-delta setting they need when the project diffs with migra. `doctor` reports what a migra diff drops from the schema files (BS713: an error for `@bsb` tags in a comment, a warning for grants and security-invoker views) and a module file whose `@bsb-hash` line a `db pull --declarative` removed (BS714). `db squash --keep` merges the `_1`, `_2` files pg-delta writes in numeric order, and migrations written by `upgrade` and `add --adopt` are created exclusively and retried on a stamp clash.
