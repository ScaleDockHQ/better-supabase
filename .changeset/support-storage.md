---
"better-supabase": minor
---

In a support session, `ctx.storage` reads Storage as the target user, where `ctx.supabase` throws. Its `from(bucket)` has `download`, `createSignedUrl` and `list`: each call first checks over Postgres, as the target, that the policies on `storage.objects` let them see the object (or which listed entries they can see), and only then reads it with the service client. `upload` is refused, with `SUPPORT_READ_ONLY` in a read-only session and `SUPPORT_STORAGE_WRITES` in a writable one. `supportStorage({ admin, sql, readOnly })` and its types are exported from `better-supabase/server` for the same check outside the server context.
