---
"better-supabase": patch
---

`gen` no longer turns the copies PostgREST lists for a view over a referenced table into relations. A view on `organizations` added a second `organization` relation to every table that references `organizations`, and the deduplication renamed the real one (`organizationByOrganization`). Relations now follow each foreign key to the table it references only.
