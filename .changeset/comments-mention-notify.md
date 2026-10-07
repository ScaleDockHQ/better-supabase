---
"better-supabase": minor
---

Comment mention notifications can be shaped or switched off. `sql.modules.comments.options.notify: false` keeps the outbox `comment.mentioned` event but sends no notification, for apps that send their own. Each `options.subjects.<type>` takes `label` and `path`, SQL on the subject row `{row}` that fills the notification's `subject_label` and `action_path`, so an adopted events table that requires a label accepts mentions, and `readableBy`, a condition on `{row}` and the mentioned `{user}`. A mentioned member is now notified only with the subject type's read key and its `permission` in the tenant, and when `readableBy` holds, instead of the tenant-wide `comments.read` alone.
