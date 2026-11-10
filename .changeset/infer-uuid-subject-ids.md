---
"better-supabase": patch
---

The inline read policies of attachments, reactions and scores compare a subject whose id column your schema files declare as `uuid` on that type, so the subject table's primary key serves the lookup without setting `idType`. The cast sits in the subject's own branch behind a uuid shape check, so a malformed stored id reads as not found. Run `better-supabase upgrade` to pick it up.
