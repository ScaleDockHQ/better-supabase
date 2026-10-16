---
"better-supabase": minor
---

`scimHandler` takes a `store`: a versioned `ScimStore` with `list`, `get`, `save` and `delete` for users and groups, which may apply the filter and paging itself. `sqlScimStore(transport)` is the default, and `transport` still works. The store gets the raw resource, extension schemas included. `blocks.sso.options.syncLog` adds a `scim_sync_log` table; pass `sqlScimSyncLog` as the handler's `log` to record each write.
