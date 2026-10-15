---
"better-supabase": minor
---

The `relations` module declares a fourth default kind, `created_from` (inverse `converted_to`, one origin per record, no cycles), for records that turn into other records. `converted_into(tenant, origin_type, origin_id, into_type)` and the client's `convertedInto` return the record an origin was already converted into, so a conversion runs once, and `lineage(organizationId, subject)` returns a record's origins and conversions. `sql sync` rewrites the relations module.
