---
"better-supabase": patch
---

The `moderation` block indexes the foreign keys of its DSA notices, flaggers and appeals tables, so
joins and cascading deletes no longer scan them. Run `better-supabase upgrade` to regenerate the
module. The MT940 parser also drops the `NOTPROVIDED` end-to-end id that German banks write when a
payment has none.
