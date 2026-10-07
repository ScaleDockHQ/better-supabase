---
"better-supabase": minor
---

The notifications block reads more of the inbox. `list` and the new `page` filter by `subjectTypes` and `search` and take a `settled` status for resolved and dismissed notifications; `page({ offset })` returns `{ items, total }` from `notification_page`. `markUnread({ ids })` clears the read time, `counts()` adds `actionableSubjects` (each subject counted once), and `subscriptions()` and `preferences()` read the caller's own settings through `list_notification_subscriptions` and `list_notification_preferences`. `list_notifications` takes `subject_types` and `search` as its seventh and eighth arguments, and `notification_counts` returns `actionable_subjects`; a module in custom mode needs the new signatures and functions.
