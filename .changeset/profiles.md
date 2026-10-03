---
"better-supabase": minor
---

Profiles and image buckets. The new `profiles` SQL kit module creates a profile on sign-up from auth metadata (full, first and last name, avatar), allocates a unique username, mirrors `auth.users.email`, grants updates only on the columns users own and refuses changes to service-owned columns (`PROFILE_COLUMN_READONLY`). It supports `mode: 'adopt'` for an existing table keyed by any column, an `after_profile_sync` hook, extra columns, a read policy for people in the same organizations and `backfill_profiles()`. `better-supabase/storage` adds `avatarBucket()` and `orgLogoBucket()` presets and a bucket policy, `{ access: { read, write } }`, that checks permissions through the SQL kit's access contract.
