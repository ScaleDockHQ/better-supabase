---
"better-supabase": minor
---

`notifications.list()` and `page()` take `read`, `resolved` and `dismissed` filters that combine with each other and with `status`, so an inbox can show a handled view (`{ resolved: true }`), unread open items (`{ read: false, resolved: false }`), dismissed items (`{ dismissed: true }`) or everything (`{ dismissed: null }`). `dismissed` defaults to `false`, and `status: "settled"` keeps listing resolved and dismissed notifications. `list_notifications` and `notification_page` take `read`, `resolved` and `dismissed` as their last arguments; the module version is 4, and `sql upgrade` drops the old signatures.
