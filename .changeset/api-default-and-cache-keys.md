---
"better-supabase": minor
---

Compare a block's `api: { schema }` with `database.sql.api`, so doctor BS427 and `codemod config --prune` report it as restated, and let the codemod set `database.sql.api` when most blocks name the same schema (it writes `api: false` on the blocks with no entry and keeps the change only when the render stays the same). BS427 now names a record type permission that repeats the provider's `actionKeys` as `recordTypes.<type>.permissions.<action>`; a doctor baseline entry for the old `subjects.` target is stale. Doctor BS715 counts, as info, the action keys the config writes that the provider's `actionKeys` could supply. The render and generator caches now include a hash of the config file and the project files it imports, and the generator cache includes the hash of the generator files, so an edit to an imported helper renders again.
