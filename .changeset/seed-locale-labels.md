---
"better-supabase": minor
---

Seeded letterheads and the shared tax keys `STD`, `RED` and `ZERO` now have English, Dutch and German text. `en` seeds those rows. The variant argument of a seed function is the brand.

`better-supabase upgrade` rewrites the document-templates and tax modules. No data migration is needed. Organizations already seeded keep their rows.
