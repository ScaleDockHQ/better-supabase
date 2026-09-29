---
'better-supabase': minor
---

Add `server.deleteAccount(userId, { buckets, cascades })`. It removes the
user's objects from buckets with an owner placeholder (`bucket.owner`), deletes
the Auth user, and emits `mutation` notices for `auth.users` and the tables in
`cascades`; `next.deleteAccount` also invalidates the user's cached session. It
returns a `Result` and never throws. Doctor reports foreign keys to
`auth.users` without `on delete cascade` or `set null` as BS406.
