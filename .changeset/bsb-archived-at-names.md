---
"better-supabase": minor
---

A soft-deleted row of the drive, memory and messaging blocks carries `archived_at` where it carried `deleted_at`. Run `better-supabase codemod naming` to write the migration that renames the three columns of an installed app, then `upgrade`. The `deletedAt` option and Row field keep their names. `auth.users.deleted_at`, the organizations block's `deleted_at` and the column an app table gets from `softDelete` stay.

| Old                                                                    | New                              |
| ---------------------------------------------------------------------- | -------------------------------- |
| `drive_nodes.deleted_at`, `memories.deleted_at`, `messages.deleted_at` | `archived_at` on the same tables |
