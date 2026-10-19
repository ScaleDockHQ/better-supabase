---
"better-supabase": patch
---

`toDbError` now classifies PostgREST and Postgres error objects, and a thrown `PostgrestError`, through `mapDbError`, so a unique violation becomes `conflict`, `PGRST116` becomes `not_found`, and permission and check failures get their kinds instead of `unexpected`. Other errors and unknown values map as before.
