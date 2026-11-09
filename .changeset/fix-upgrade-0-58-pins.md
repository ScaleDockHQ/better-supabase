---
"better-supabase": minor
---

`codemod naming` keeps working for apps that own a block table. It writes a `blocks.<name>.columns` entry that keeps the old name of a column your own table still has (`drive_nodes.deleted_at`, the actor columns of scorecards and status history), so the feature that reads it stays on, and it renames the block column names in your schema files and seeds, only in statements that name a `better_supabase` table and never in migrations. Blocks now leave out a unique index over the same columns as a unique key of yours, the invoices number key when your key is a subset of it, and their own `updated_at` trigger on a table your files track with `track_updated_at()`, so doctor BS623 and BS624 report only what a block can't decide.
