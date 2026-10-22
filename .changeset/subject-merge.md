---
"better-supabase": minor
---

Merging two companies or two people now moves the dropped record's comments, attachments, reactions, tags, relations and guest grants to the kept record in the same transaction.

- Each module that stores rows per subject installs a merge handler, and `better_supabase.merge_subject_refs(subject_table, keep, drop)` runs them all. Rows the kept record already has (the same reaction, tag or guest grant) are dropped instead of duplicated.
- Apps can move their own tables in the same merge with a `security definer` function marked `better-supabase:subject-merge`. See Merging subject records on the SQL modules page.
- Run `better-supabase sql sync` and generate a migration to install the handlers. The `company.merged` and `person.merged` events still fire, so existing consumers keep working.
