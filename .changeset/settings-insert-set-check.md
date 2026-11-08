---
"better-supabase": minor
---

The organization settings insert policy checks the tenant with `tenant_ids_with` instead of one `can()` call per row. The attachments insert policy still calls `can()` because its permission depends on the subject type.

`better-supabase upgrade` rewrites the `settings` and `read-sets` modules (the second because counts are now estimated) and the next schema migration replaces one policy. No data migration is needed.
