---
"better-supabase": patch
---

Doctor BS112 now counts a call to `better_supabase.is_service_role()` as a caller check, so a security definer function that only the service role may run is no longer reported.
