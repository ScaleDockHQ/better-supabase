---
"better-supabase": minor
---

`better-supabase codemod 0.29` renames the `records` config key back to `subjects`, which reverses the `subjects` to `records` rename that `codemod 0.15` made. It renames the key inside `$env.*` and `$<environment>` blocks too, and merges the entries into an existing `subjects` key (those entries win) with a line to review. It also renames the `@bsb record` tag in the table comments of `supabase/schemas/*.sql` to `@bsb subject`, and leaves migrations alone.
