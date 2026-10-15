---
"better-supabase": minor
---

`ctx.storage` writes in a writable support session. `upload`, `update`, `remove`, `copy`, `move` and `purgeCache` first run the row change Storage would make as the target, inside a savepoint that is rolled back, so the policies on `storage.objects` decide with `owner_id` set to the target. A refused dry run resolves to Storage's `403` error (`AccessDenied`) with the policy's message. Then the service client writes, the admin Postgres connection makes the target the owner of the stored object, and its `user_metadata` records `supportSessionId` and `supportAdminId`. `remove` deletes only the paths the target may delete. Signed uploads still resolve to `SUPPORT_STORAGE_WRITES`, and a read-only session still refuses every write with `SUPPORT_READ_ONLY`.

`supportStorage` takes `adminSql` and `session` for writes. `attachments.put` no longer creates a signed upload URL before it uploads, so it works in a writable support session.
