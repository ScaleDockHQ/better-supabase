---
"better-supabase": patch
---

`activities_of`, `list_attachments` and `read_field_values` now log a read of the record they
return when its subject type sets `auditReads`. Nothing is logged for an empty result or a list
that names no single record. Apply the new migration with `better-supabase upgrade`.
