---
"better-supabase": minor
---

`notifications.bulk(ids, action)` marks many notifications `read` or `unread`, or dismisses them, and `moderation.bulk(ids, decision)` applies one decision to many items. Both return the common `{ succeeded, failed: [{ id, error }] }`, and fail with `BULK_TOO_MANY` beyond 500 ids. `markRead`, `markUnread`, `dismiss` and `decide` keep working. `NotificationBulkAction` is exported from `better-supabase/blocks/notifications`.
