---
"better-supabase": minor
---

`share-links` checks a record's `share` action from `config.records` when its type declares one: `create_share_link` needs it on the record (as the caller, so per-row grants and owner columns count), and `revoke_share_link` and `list_share_links` need it on top of the organization key unless the caller created the link. `options.tokenHash` adds a caller-made `token_hash` to `create_share_link` and a non-consuming `find_share_link(token_hash)`; `options.fullRows` makes `list_share_links` return the tenant, subject, creator and creation time and take `include_revoked`. The client gains `createHashed`, `find` and a `list` filter. Without a `share` action and the options the module renders as before.
