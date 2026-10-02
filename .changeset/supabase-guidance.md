---
"better-supabase": patch
"@better-supabase/cli": patch
---

The `better-supabase` skill's schema workflow now asks for RLS, policies, policy indexes and Data API grants on every new table, and points to Supabase's own skills. The CLI asks for an access token scoped to the project when it reads a hosted project.
