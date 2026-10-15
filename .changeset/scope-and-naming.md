---
"better-supabase": minor
---

Blocks run per tenant, per user or in one shared space. `sql.scope` sets the scope of every block and `blocks.<name>.scope` the scope of one. Outside `tenant` scope a block needs neither the `tenant` module nor the access contract, its scope column is nullable (the user's id by default in `user` scope), and its functions set the scope id themselves. `tags` and `comments` run in every scope, the blocks without tenant data (such as `notifications`) run anywhere, and blocks that need tenants declare `scopes: ["tenant"]`, so `sql add` and `resolvePreset` refuse them in another scope.

`sql.naming.tenant` renames the tenant concept in the tables, columns and functions the blocks write: `workspace` gives `workspaces`, `workspace_id`, `create_workspace` and `member_workspace_ids`. `blocks.<name>.functions` renames single functions. A tenant name that would collide with a block's own names is refused. `gen` writes the names into each block's `naming` in `blocks.generated.ts`, and `defineBlocks` wraps the block's transport with the new `blockNames()` middleware, so the block clients call the renamed functions. The preset model's `tenantName` field takes `workspace` and `team`, and presets write `sql.scope` and `sql.naming`.

The SQL modules check access only through `ctx.scope` (`can`, `ids`, `check`, `canUser`, `platform`, `members`), and `canIn` and `tenantIn` are removed from the module helpers. `tags.update_tag` no longer fails with an ambiguous `name` column.
