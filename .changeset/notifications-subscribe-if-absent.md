---
"better-supabase": minor
---

`notifications.subscribe({ userId, level, ifAbsent: true })` adds a level for another member only when they have none for the subject, so an auto-follow (the author, an assignee or a replier) keeps a member's own `ignore` or `all`. With `ifAbsent`, a signed-in sender with the send permission in the tenant may set it for a member of that tenant, not only the service. `set_notification_subscription` takes `if_absent boolean default false` as a sixth argument; a module in custom mode needs that signature.
