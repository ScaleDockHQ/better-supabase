---
"better-supabase": minor
---

The comments module (version 4) filters activity per record when the `subjects` module is installed: the read policy on `activity_entries` checks `can_subject(subject_type, subject_id, 'read')` for every registered subject type, and `list_activity` returns an empty timeline for a subject the caller can't read. Members no longer see entries on records they can't read, or on deleted records. Entries without a subject, or on a type the registry doesn't list, keep the tenant check alone.

With the audit module installed with `options.readPolicy: true`, a subject's timeline also returns the audit log entries for its row, gated by the audit read policy. `ActivityEntry` has a new `source` field (`ActivitySource`, `"event"` or `"audit"`), so code that builds `ActivityEntry` values by hand needs to set it.

With the notifications module installed, the author of a comment and the users it mentions follow the subject as `participating` watchers in `notification_subscriptions`; an existing row, such as `ignore`, is kept. `options.follow: false` turns this off. Run `sql sync` to rewrite the installed module.
