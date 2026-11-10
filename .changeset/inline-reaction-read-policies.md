---
"better-supabase": patch
---

The reaction and score read policies check the subject inline instead of calling `reaction_subject_visible` once per row. Counting 12,000 reactions as a member takes 20 ms instead of 4,863 ms. Run `better-supabase upgrade` and generate the migration.
