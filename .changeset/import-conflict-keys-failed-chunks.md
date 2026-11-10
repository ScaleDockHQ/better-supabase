---
"better-supabase": minor
---

An import batch names the keys of its conflicted items (`conflictKeys`, the first 100), and a worker can mark a stored chunk failed with `imports.chunks.fail`, so a queue stops retrying it. `chunks.progress` counts `failed` chunks and `chunks.process` answers `{ status: "failed", message }` for one. Run `better-supabase upgrade` and generate the migration: it adds the `fail_import_chunk` function and the `failed` chunk status.

The subject cascade deletes of `approvals` and `relations` read an index. Approval requests get a `(subject_type, subject_id)` index, relations get a tenant-led source index, and the relations cascade filters on the subject row's tenant. The drive retention sweep asks the retention and hold policies once per tenant and statement.
