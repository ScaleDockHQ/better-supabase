---
"better-supabase": patch
---

The drive block takes an optional `permissions.delete` key. When it is set, `delete(id)` (`drive_delete`, which skips the bin) and `purge(binId)` also need that tenant key next to the share role, so an app whose share role is its editing role can keep hard deletes for the members that hold the key. Run `better-supabase upgrade` after setting it.
