---
"better-supabase": minor
---

Add the `trash` block (`better-supabase/blocks/trash` and the `trash` SQL module): soft delete through each subject's `deletedAt` column, children trashed in the same batch, restore with unique column checks, a list per organization, `purge()`, `purge_expired_trash()` after `retentionDays`, and `is_trashed()` for policies. The module records `subject.trashed`, `subject.restored` and `subject.purged`.
