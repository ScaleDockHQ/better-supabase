---
"better-supabase": minor
---

An app table can be a subject: `appTables.<name>.subject` takes a `type`, a `title` and `url`, `search`, `permissions`, `rank` and `softDelete`, and is merged into `subjects`. Comments, attachments, tags, versions, watchers, activity and search then reach its rows. `rank: true` adds a `rank` column with an index and `softDelete` adds `deleted_at`. A design that uses `subject` writes design format 2.

Migration: none for existing configs. A type in `subject` that is already in `subjects` fails `resolveConfig`; remove one of the two.

Create gets a Features tab on the table inspector: turning on comments, attachments, tags, versions or search adds the block and makes the table a subject, and the table shows a badge for each feature.
