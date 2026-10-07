---
"better-supabase": minor
---

The `webhooks-in` module checks separate `create`, `update` and `delete` permission keys, each `webhooks.manage` by default. `sql.modules.webhooks-in.permissions.manage` still sets all three, and `create`, `update` or `delete` override one of them. `modulePermissionKeys` lists the three actions instead of `manage`, so a PermDock catalog check sees the keys the functions check.
