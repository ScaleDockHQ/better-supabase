---
"better-supabase": patch
---

Profiles: a `usernameFrom` entry `{ columns, separator }` joins the values `sync_profile` writes to the profile's own columns (after `metadata` and `splitName`), so a sign-up with only `full_name` gets `grace.hopper`. Usernames keep the `.` or `-` of a configured separator, in `allocate_username` and in the managed username check. The service-column guard never rejects a change to `updated_at`, and only sets it on a managed table, so an adopted table's own `updated_at` trigger keeps working.
