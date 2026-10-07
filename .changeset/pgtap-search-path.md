---
"better-supabase": patch
---

The pgTAP kit's `tests.authenticate_as`, `tests.authenticate_as_anon` and `tests.clear_authentication` set `search_path`. The helpers stay installed after `supabase test db`, so a later `supabase db advisors` run reported `function_search_path_mutable` for them. A unit test now checks that every function the modules and the kit create sets its `search_path`.
