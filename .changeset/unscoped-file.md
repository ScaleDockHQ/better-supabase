---
"better-supabase": minor
---

`upgrade` writes event triggers and triggers on `auth` tables to one file, `900_better_supabase_999_unscoped.sql`, instead of into six module files. The workflow-sdk module grants its sequences by name, not with `on all sequences`. Run `better-supabase upgrade`; the migrations workflow keeps each statement in its module.
