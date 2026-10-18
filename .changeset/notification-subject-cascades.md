---
"better-supabase": minor
---

The `notifications` module takes `options.subjects` like the other subject-bound modules. A subject type with `cascade: true` gets an `after delete` trigger on its table that deletes the subject's notifications, with their recipients and deliveries, and the subscriptions to it. Without `options.subjects` the module reads `config.subjects`, so a registered type with `cascade: true` now cleans up its notifications too. The keys may contain hyphens (`time-off-request`), because `subject_type` in `notification_events` takes any text.
