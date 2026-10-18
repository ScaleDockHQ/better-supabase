---
"better-supabase": patch
---

Three SQL modules pass `supabase db lint` again when more blocks are installed. `save_view` and `set_user_state` no longer fail with an ambiguous column reference, and the forms module reads an adopted custom field options table without a constant query that plpgsql_check rejects when the table is missing. The saved-views indexes are now named after their tables, so renaming `views` or `preferences` no longer collides with another install's index names. Run `better-supabase sql sync` and generate a migration.
