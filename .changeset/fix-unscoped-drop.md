---
"better-supabase": patch
---

Stop writing `drop event trigger if exists` into the declarative `900_better_supabase_999_unscoped.sql` file, which `supabase db schema declarative sync` rejects. `better-supabase sql upgrade --check` now fails when a declarative module file contains a `drop event trigger` line. Run `better-supabase upgrade` to rewrite the file.
