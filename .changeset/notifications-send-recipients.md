---
"better-supabase": minor
---

Breaking: `notifications.send()` returns `{ id, recipients }` instead of the id, with the user ids that hold the notification after watchers, the audience hook, preferences and the read filter are applied, or `null` when nobody was left. `onSent` and the `notification.created` block event get the same recipients instead of the `recipients` input. It calls the new `send_notification(jsonb)`, which returns `{ "id", "recipients" }`; `notify(jsonb)` still returns the id.
