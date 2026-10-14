---
"better-supabase": patch
---

The teams module's `update_team` function qualifies its column references, so plpgsql_check no longer reports `name` as ambiguous and the update no longer fails at runtime.
