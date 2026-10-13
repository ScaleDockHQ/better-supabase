---
"better-supabase": minor
---

Subject events share one shape, and watchers can follow them.

- Every subject event (`comment.*`, `subject.tagged`, `subject.untagged`, `status.changed`, `field_value.set`, `share_link.created`, `subject.viewed`, `reminder.sent`) carries `organizationId`, `subjectType` and `subjectId`, typed as `SubjectEventData` from `better-supabase/events`.
- `watcherHandler(notifications, { types })` from `better-supabase/blocks/notifications` turns outbox rows (`outbox.consume`) into notifications for the subject's watchers, keyed by the event id, and leaves out the actor the row records. `watcherSink` does the same for CloudEvents, leaving out an actor the event data names.
- `status.changed` now carries the subject's tenant, the previous status in `from` and the `reason`. The table trigger records it, so a direct update or `rank.move()` into a new status emits it too, and an update that keeps the status emits nothing.
- `transition()` clears its reason when it returns, so a later direct update in the same transaction no longer writes that reason to the history row.
- `reminder.sent` now carries `subjectType`, `subjectId` and `userId`.
- `mark_reminder_sent` no longer fails with an ambiguous `occurrence_at` reference, and a second delivery of the same occurrence returns `false` and records no second event.
- `reminders.deliver(payload)` and `reminders.job` deliver one occurrence. With `reminderNotification`, `createBlocks` wires them to the `notifications` block (`REMINDER_DELIVERY_QUEUE` names the queue).
