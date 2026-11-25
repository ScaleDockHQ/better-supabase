---
"better-supabase": minor
---

A restore (`restore_data_row`, the `data_lifecycle_row` import entity) no longer writes the tables that decide access, billing, usage, keys or platform state, such as memberships, permission overrides, usage quotas, billing subscriptions and support sessions, and `data_restore_tables()` leaves them out. `blocks.data-lifecycle.options.restoreExclude` lists tables of your own to leave out as well. The member who started the import run needs `permissions.restore` (`organization.delete` by default), so an admin with only the import key can't restore. Run `better-supabase upgrade` to regenerate the data-lifecycle module. Upgrade note: a restore started by a member without the restore key (`organization.delete` unless you set `permissions.restore`) now fails every row.
