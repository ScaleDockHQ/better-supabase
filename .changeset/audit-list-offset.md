---
"better-supabase": minor
---

`createAuditLog().list()` and `export()` take `offset`, and `list_audit_events` takes `skip`. Next to `count: true`, a table with page numbers and a total can open page N directly instead of walking the cursor from the first page.
