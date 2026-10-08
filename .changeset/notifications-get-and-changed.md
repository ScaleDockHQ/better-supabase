---
"better-supabase": minor
---

`notifications.get(id, { locale?, include? })` reads one of the caller's notifications (`get_notification(id)`), rendered like a list item, or `null`. Breaking: `markRead`, `markUnread`, `dismiss` and `resolve` return `{ count, items }` instead of a number, with the caller's own notifications as they are after the change, and `mark_notifications_read`, `mark_notifications_unread`, `dismiss_notifications` and `resolve_notifications` return that object as `jsonb` instead of an `integer`. Read the count from `.count`. The module file drops the `integer` versions before it creates the new ones. API schema wrappers (`sql.modules.<module>.api`) also drop the wrappers of the signatures their module drops, so a wrapper whose return type changed is recreated.
