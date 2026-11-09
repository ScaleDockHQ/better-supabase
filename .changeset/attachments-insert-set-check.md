---
"better-supabase": minor
---

The attachments insert policy checks the upload permission with the tenant sets instead of one `can()` call per row, so no block policy of any module calls `can()` per row any more (a registry test holds it for `using` and `with check`).

`better-supabase upgrade` rewrites the attachments module and the next schema migration replaces one policy. No data migration is needed.
