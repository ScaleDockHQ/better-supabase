---
"better-supabase": minor
---

Module files no longer paste the helpers they call. `better-supabase upgrade` writes one `900_better_supabase_000_prelude.sql` that defines the `better_supabase` schema, the `blocks` table, `actor_may_write`, `raise_actor_readonly`, `acting_member`, the column type helpers, `import_run`, `merge_subject_refs`, the memo functions and `replace_equivalent_triggers` once. Commit it with the module files. Without a memberships block, the prelude also defines an empty `member_organization_ids`, where each module used to create it in a `do` block.
