---
"better-supabase": patch
---

Fix block findings from the no-code research review.

- `create_share_link` checks that the subject exists in the link's tenant and that the caller can read it, and raises `SHARE_SUBJECT_NOT_FOUND` or `SHARE_SUBJECT_UNKNOWN` otherwise. Links take `maxUses`, and `resolve_share_link` counts each use, so a spent link stops resolving. `drive_link` and `get_shared_ai_chat` also check the link's tenant.
- `runImport` marks an import `failed` with the rows it inserted when a batch throws, instead of leaving it `running`. A new `running` hook (with `mark_import_running` in SQL) marks it running before the first batch.
- A number sequence refuses a number set by hand unless the service role sets it (`NUMBER_MANUAL`).
- `save_view` drops `isDefault` when the view moves to another scope, list or team.
- The app tables pgTAP file inserts a row of another tenant or user before it checks that a signed-in user can't read it, so the check fails when a policy leaks rows.
