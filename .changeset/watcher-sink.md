---
"better-supabase": minor
---

Subject events share one shape, and watchers can follow them.

- Every subject event (`comment.*`, `subject.tagged`, `subject.untagged`, `status.changed`, `field_value.set`, `share_link.created`, `subject.viewed`, `reminder.sent`) carries `organizationId`, `subjectType` and `subjectId`, typed as `SubjectEventData` from `better-supabase/events`.
- `watcherSink(notifications, { types })` from `better-supabase/blocks/notifications` turns those events into notifications for the subject's watchers, keyed by the event id.
- `status.changed` now carries the subject's tenant and the previous status in `from`.
- `reminder.sent` now carries `subjectType`, `subjectId` and `userId`.
- `mark_reminder_sent` no longer fails with an ambiguous `occurrence_at` reference, and a second delivery of the same occurrence returns `false` and records no second event.
- `reminders.deliver(payload)` and `reminders.job` deliver one occurrence. With `reminderNotification`, `createBlocks` wires them to the `notifications` block (`REMINDER_DELIVERY_QUEUE` names the queue).
