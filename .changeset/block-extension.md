---
"better-supabase": minor
---

Blocks can be extended without forking them: add your own columns and type them, steer methods with hooks, wrap the transport and add methods.

- `options.extraColumns` on the `organizations` and `profiles` SQL modules adds your own columns to the managed table, copies them on writes and returns them from reads. `list_my_organizations` returns the attribute and extra columns in a new `attributes jsonb` column.
- A Standard Schema `fields` option on `createOrganizations` and `createProfiles` types those columns, parses them on read and turns a bad write into a `validation` error. `createNotifications` parses stored `data` with its type's schema on `get`, `list` and `page`, so `item.data` narrows on `item.type` (`NotificationOf`); data the schema rejects fails with the hint `NOTIFICATION_DATA_INVALID`.
- A `hooks` option on those blocks, and on `createBlocks` keyed by block name, runs `before` hooks that refuse a call with a `DbError` or replace its arguments, and `after` hooks that observe a copy of the result. `withBlockHooks` does the same for any block.
- New SQL hooks: `before_organization_update`, `after_organization_update`, `before_profile_update`, `after_profile_update` and `before_notification_send`.
- `wrapTransport` runs versioned `BlockTransportMiddleware` around every block call, checked by `testBlockTransportMiddleware` in `better-supabase/testing`, and `extendBlock` adds methods and refuses to redefine one.
