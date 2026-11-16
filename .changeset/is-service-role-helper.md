---
"better-supabase": minor
---

Add `better_supabase.is_service_role()` to the prelude: true for the `service_role` key and a direct admin connection, so your own service-only SQL functions call one helper instead of copying the `auth.jwt() ->> 'role'` check.
