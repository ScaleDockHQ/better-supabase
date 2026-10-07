---
"better-supabase": patch
---

`defineBucket(...).sql()` bounds `name` to the tenant's or owner's prefix when that segment comes first in the path, so Postgres reads one tenant's objects through the storage name index instead of scanning the whole bucket. Apply the new `.sql()` output in a migration to pick up the policies.
