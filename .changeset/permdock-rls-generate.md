---
'better-supabase': patch
---

The docs now name the right PermDock command for the SQL helpers. `permdock_has` and `permitted_<scope>_ids` come from `permdock rls generate`, not from `permdock supabase hook generate`. The PermDock guide gains a setup step that runs both commands, and says that the helpers live in PermDock's `rls.schema`, which must equal the `schema` option on buckets and topics.
