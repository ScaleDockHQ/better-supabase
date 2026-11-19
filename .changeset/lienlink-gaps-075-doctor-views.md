---
"better-supabase": patch
---

Doctor BS635 no longer suggests an `include` on a view that has the name of a table in another schema, such as a `public.memberships` view over `better_supabase.memberships`. A repository reads the view, which has no relations.
